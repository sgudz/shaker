#!/bin/bash
#set -x
#This script should be run from the Master node in order to install and launch Shaker
#This script tests "storage" network for test between nodes. You can change network by replacing NETWORK parameter(to do).
export DATE=`date +%Y-%m-%d_%H:%M`

if $CREATE_NEW_RUN;then
	curl -H "Content-Type: application/json" -u "sgudz@mirantis.com:Kew4SZEQ" -d '{"suite_id": '$SUITE_ID',"name": "to_delete4","assignedto_id": 89,"include_all": true}' "https://mirantis.testrail.com/index.php?/api/v2/add_run/3" > run_data.json
	RUN_ID=$(grep -Po '"id":.*?[^\\]"' run_data.json | grep -Po "[0-9]*")

########################## Get tests from RUN ###############################
curl -H "Content-Type: application/json" -u "sgudz@mirantis.com:Kew4SZEQ" "https://mirantis.testrail.com/index.php?/api/v2/get_tests/$RUN_ID" > tests_$RUN_ID.json
TESTS_IDS=$(grep -Po '"id":.*?[^\\]"' tests_$RUN_ID.json | grep -Po "[0-9]*")

################## Define test case from testrail #######################
if $DVR && $VXLAN && $OFFLOADING;then
	TEST_ID=$(echo ${TEST_IDS} | tr " " "\n" | awk '(NR == 3)')
elif $DVR && $VLAN && $OFFLOADING;then
        TEST_ID=$(echo ${TEST_IDS} | tr " " "\n" | awk '(NR == 4)')
elif $DVR && $VXLAN;then
        TEST_ID=$(echo ${TEST_IDS} | tr " " "\n" | awk '(NR == 1)')
elif $DVR && $VLAN;then
        TEST_ID=$(echo ${TEST_IDS} | tr " " "\n" | awk '(NR == 2)')
elif $L3HA && $VXLAN && $OFFLOADING && $BETWEEN_NODES;then
        TEST_ID=$(echo ${TEST_IDS} | tr " " "\n" | awk '(NR == 5)')
elif $L3HA && $VXLAN && $OFFLOADING;then
        TEST_ID=$(echo ${TEST_IDS} | tr " " "\n" | awk '(NR == 6)')
elif $L3HA && $VLAN && $OFFLOADING && $BETWEEN_NODES;then
        TEST_ID=$(echo ${TEST_IDS} | tr " " "\n" | awk '(NR == 7)')
elif $L3HA && $VLAN && $OFFLOADING;then
        TEST_ID=$(echo ${TEST_IDS} | tr " " "\n" | awk '(NR == 8)')
else
	echo "Wrong configuration for test"
	exit 1

fi

####################### Catching scenarios ##############################################################################################
curl -s 'http://172.16.44.5/for_workarounds/shaker_scenario_for_perf_labs/nodes.yaml' > nodes.yaml
curl -s 'http://172.16.44.5/for_workarounds/shaker_scenario_for_perf_labs/VMs.yaml' > VMs.yaml

######### Get cases JSON data from suite ##################
curl -H "Content-Type: application/json" -u "sgudz@mirantis.com:Kew4SZEQ" "https://mirantis.testrail.com/index.php?/api/v2/get_cases/3&suite_id=$SUITE_ID" > cases.json
cat cases.json

if $CREATE_NEW_RUN;then
  curl -H "Content-Type: application/json" -u "sgudz@mirantis.com:Kew4SZEQ" -d '{"suite_id":'${SUITE_ID}',"name": "to_delete3","assignedto_id": 89,"include_all": true}' "https://mirantis.testrail.com/index.php?/api/v2/add_run/3"
fi

export SSH_OPTS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet'
CONTROLLER_ADMIN_IP=`fuel node | grep controller | awk -F "|" '{print $5}' | sed 's/ //g'`

export CONTROLLER_PUBLIC_IP=$(ssh ${CONTROLLER_ADMIN_IP} "ifconfig | grep br-ex -A 1 | grep inet | awk ' {print \$2}' | sed 's/addr://g'")
echo "Controller Public IP: $CONTROLLER_PUBLIC_IP"

#Define 2 computes IPs for testing between nodes
COMPUTE_IP_ARRAY=`fuel node | awk -F "|" '/compute/ {print $5}' | sed 's/ //g' | head -n 2`
echo "Compute IPs:"
for i in ${COMPUTE_IP_ARRAY[@]};do echo $i;done

# Update traffic.py file to have stdev and median values in the report
curl -s 'https://raw.githubusercontent.com/vortex610/shaker/master/traffic.py' > traffic.py

##################################### Run Shaker on Controller ########################################################################
echo "Install Shaker on Controller"
REMOTE_SCRIPT=`ssh $CONTROLLER_ADMIN_IP "mktemp"`
ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "cat > ${REMOTE_SCRIPT}" <<EOF
#set -x

source /root/openrc
SERVER_ENDPOINT=$CONTROLLER_PUBLIC_IP
printf 'deb http://ua.archive.ubuntu.com/ubuntu/ trusty universe' > /etc/apt/sources.list
apt-get update
apt-get -y install iperf python-dev libzmq-dev python-pip && pip install pbr pyshaker

iptables -I INPUT -s 10.20.0.0/16 -j ACCEPT
iptables -I INPUT -s 10.0.0.0/16 -j ACCEPT
iptables -I INPUT -s 172.16.0.0/16 -j ACCEPT
iptables -I INPUT -s 192.168.0.0/16 -j ACCEPT

shaker-image-builder --flavor-vcpu 8 --flavor-ram 4096 --flavor-disk 55 --debug

#Copy orig traffic.py
cp /usr/local/lib/python2.7/dist-packages/shaker/engine/aggregators/traffic.py /usr/local/lib/python2.7/dist-packages/shaker/engine/aggregators/traffic.py.orig
EOF
#Run script on remote node
ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "bash ${REMOTE_SCRIPT}"

##################################### Copying scenarios to right directory ##############################################################
echo "Copying required files to specific directories"
scp nodes.yaml $CONTROLLER_ADMIN_IP:/usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/
scp VMs.yaml $CONTROLLER_ADMIN_IP:/usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/
scp traffic.py $CONTROLLER_ADMIN_IP:/usr/local/lib/python2.7/dist-packages/shaker/engine/aggregators/traffic.py
##################################### Install Shaker on computes #########################################################################
sleep 5
if $BETWEEN_NODES;then
echo "Install Shaker on Computes and launch local agents"
cnt="1"
for item in ${COMPUTE_IP_ARRAY[@]};do
	REMOTE_SCRIPT2=`ssh ${SSH_OPTS} $item "mktemp"`
	ssh ${SSH_OPTS} $item "cat > ${REMOTE_SCRIPT2}" <<EOF
#set -x
printf 'deb http://ua.archive.ubuntu.com/ubuntu/ trusty universe' > /etc/apt/sources.list
apt-get update
apt-get -y install iperf python-dev libzmq-dev python-pip && pip install pbr pyshaker

iptables -I INPUT -s 10.20.0.0/16 -j ACCEPT
iptables -I INPUT -s 10.0.0.0/16 -j ACCEPT
iptables -I INPUT -s 172.16.0.0/16 -j ACCEPT
iptables -I INPUT -s 192.168.0.0/16 -j ACCEPT
EOF
	ssh ${SSH_OPTS} $item "bash ${REMOTE_SCRIPT2}"
	agent_id="a-00$cnt"
	ssh ${SSH_OPTS} $item "screen -dmS shaker-agent-screen shaker-agent --server-endpoint=$CONTROLLER_ADMIN_IP:19000 --agent-id=$agent_id"
	cat ${REMOTE_SCRIPT2}

################################## Changing test files for agent and IP's roles ############################################################

	if test $agent_id == "a-001";then
		role="master"
		ip=`ssh ${SSH_OPTS} $item ifconfig | grep "192.168.1." | awk -F ":" '{print $2}' | awk -F " " '{print $1}'`
		FOR_SED="ip: $ip"
		MASTER_IP=`ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "sed -n '11p;11q' /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/nodes.yaml | sed 's/    //g'"`
		ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "sed -i 's/${MASTER_IP}/${FOR_SED}/g' /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/nodes.yaml"
		ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP cat /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/nodes.yaml | head -n 13
	else
		role="slave"
		ip=`ssh ${SSH_OPTS} $item ifconfig | grep "192.168.1." | awk -F ":" '{print $2}' | awk -F " " '{print $1}'`
		FOR_SED="ip: $ip"
		SLAVE_IP=`ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "sed -n '16p;16q' /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/nodes.yaml | sed 's/    //g'"`
		ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "sed -i 's/${SLAVE_IP}/${FOR_SED}/g' /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/nodes.yaml"
		ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP cat /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/nodes.yaml | head -n 18
	fi
	echo "$agent_id launched. IP is $ip. Role is $role"

################################ If slave - launch iperf server ##############################################################################

	ssh ${SSH_OPTS} $item "screen -dmS iperf-screen iperf -s"
	cnt=$[cnt+1]
	sleep 2
done

############################## Runing scenarios ##############################################################################################

echo "Run scenarios for Nodes"
REMOTE_SCRIPT4=`ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "mktemp"`
ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "cat > ${REMOTE_SCRIPT4}" <<EOF
#set -x
source /root/openrc
SERVER_ENDPOINT=$CONTROLLER_PUBLIC_IP
SERVER_PORT2=19000
echo "SERVER_ENDPOINT: \$SERVER_ENDPOINT:\$SERVER_PORT"
shaker --server-endpoint \$SERVER_ENDPOINT:\$SERVER_PORT2 --scenario /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/nodes.yaml --report nodes_$DATE.html --debug
EOF
ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "bash ${REMOTE_SCRIPT4}"
else
	echo "Run scenarios for VMs"
	REMOTE_SCRIPT3=`ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "mktemp"`
	ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "cat > ${REMOTE_SCRIPT3}" <<EOF
#set -x
source /root/openrc
SERVER_ENDPOINT=$CONTROLLER_PUBLIC_IP
SERVER_PORT=18000
shaker --server-endpoint \$SERVER_ENDPOINT:\$SERVER_PORT --scenario /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/VMs.yaml --report VMs_$DATE.html --debug
EOF
	ssh ${SSH_OPTS} $CONTROLLER_ADMIN_IP "bash ${REMOTE_SCRIPT3}"
fi
#################### Cleaning after nodes testing ########################################
for proc in ${COMPUTE_IP_ARRAY[@]};do
	ssh ${SSH_OPTS} $proc "ps -ef | grep iperf | awk '{print \$2}' | xargs kill"
	ssh ${SSH_OPTS} $proc "ps -ef | grep shaker | awk '{print \$2}' | xargs kill"
done

########################## Copying reports to Fuel master node ###########################
export BUILD=`cat /etc/fuel_build_id`
scp $CONTROLLER_ADMIN_IP:/root/VMs_$DATE.html /root/VMs_build\-$BUILD\-$DATE.html
scp $CONTROLLER_ADMIN_IP:/root/nodes_$DATE.html /root/nodes_build\-$BUILD\-$DATE.html
CUSTOM_THROUGHPUT_NODES=$(grep -Po '"median":.*?[^\\]",' /root/nodes_build\-$BUILD\-$DATE.html | sed 's/\,\ \"unit\"\:\ \"Mbit\/s\"\,$//' | grep -Eo "[0-9]*" | awk '(NR == 1)')
CUSTOM_THROUGHPUT_VMS=$(grep -Po '"median":.*?[^\\]",' /root/VMs_build\-$BUILD\-$DATE.html | sed 's/\,\ \"unit\"\:\ \"Mbit\/s\"\,$//' | grep -Eo "[0-9]*" | awk '(NR == 1)')
CUSTOM_STDEV_NODES=$(grep -Po '"median":.*?[^\\]",' /root/nodes_build\-$BUILD\-$DATE.html | sed 's/\,\ \"unit\"\:\ \"Mbit\/s\"\,$//' | grep -Eo "[0-9]*" | awk '(NR == 3)')
CUSTOM_STDEV_VMS=$(grep -Po '"median":.*?[^\\]",' /root/VMs_build\-$BUILD\-$DATE.html | sed 's/\,\ \"unit\"\:\ \"Mbit\/s\"\,$//' | grep -Eo "[0-9]*" | awk '(NR == 3)')
echo "1. Custom throughput nodes $CUSTOM_THROUGHPUT_NODES"
echo "2. Custom throughput VMs $CUSTOM_THROUGHPUT_VMS"
echo "3. Custom stdev nodes $CUSTOM_STDEV_NODES"
echo "4. Custom stdev VMs $CUSTOM_STDEV_VMS"
echo "Done."
