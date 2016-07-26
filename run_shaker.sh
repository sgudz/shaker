#!/bin/bash
#set -x
#This script should be run from the Master node in order to install and launch Shaker
#This script tests "storage" network for test between nodes. You can change network by replacing NETWORK parameter(to do).
export DATE=`date +%Y-%m-%d_%H:%M`

####################### Catching scenarios ##############################################################################################
curl -s 'https://raw.githubusercontent.com/vortex610/shaker/master/nodes_ALL.yaml' > nodes.yaml
curl -s 'https://raw.githubusercontent.com/vortex610/shaker/master/VMs_ALL.yaml' > VMs.yaml

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
curl -s 'https://raw.githubusercontent.com/vortex610/shaker/master/openrc.patch' | patch -f /root/openrc
source /root/openrc
SERVER_ENDPOINT=$CONTROLLER_PUBLIC_IP
echo "SERVER_ENDPOINT: \$SERVER_ENDPOINT:\$SERVER_PORT"
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

############################### Runing scenarios ##############################################################################################

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

##################### Cleaning after nodes testing ########################################
for proc in ${COMPUTE_IP_ARRAY[@]};do
	ssh ${SSH_OPTS} $proc "ps -ef | grep iperf | awk '{print \$2}' | xargs kill"
	ssh ${SSH_OPTS} $proc "ps -ef | grep shaker | awk '{print \$2}' | xargs kill"
done

########################### Copying reports to Fuel master node ###########################
export BUILD=`cat /etc/fuel_build_id`
scp $CONTROLLER_ADMIN_IP:/root/VMs_$DATE.html /root/VMs_build\-$BUILD\-$DATE.html
scp $CONTROLLER_ADMIN_IP:/root/nodes_$DATE.html /root/nodes_build\-$BUILD\-$DATE.html
echo "Done."
