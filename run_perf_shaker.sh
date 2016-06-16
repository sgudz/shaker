#!/bin/bash

#This script should be run from the Master node in order to install and launch Shaker agents
set -x

#Define global variables
# Define SSH template:
SSH_OPTS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
SSH_CMD="ssh root@"
SCP_CMD="scp root@"
USER_NAME=root
CONTROLLER_ADMIN_IP=10.20.0.17

export CONTROLLER_PUBLIC_IP=$($SSH_CMD${CONTROLLER_ADMIN_IP} "ifconfig | grep br-ex -A 1 | grep inet | awk ' {print \$2}' | sed 's/addr://g'")
echo "Controller Public IP: $CONTROLLER_PUBLIC_IP"

#Define compute IPs
COMPUTE_IP_ARRAY=($(fuel node | grep '| 3       |' | awk '/compute/ {print $9}')) #Array of controller IPs in HA case
#Print out Controllers IPs
echo "Compute IPs:"
for i in ${COMPUTE_IP_ARRAY[@]};
do
    echo $i
    done

# Update traffic.py file to have stdev and median values in the report
#get new traffic.py file
#wget -nc https://raw.githubusercontent.com/esboych/Openstack-Scripts/master/SHAKER_LAUNCH_AUTOMATION/traffic.py

#copy it to Controller node
#scp traffic.py root@$CONTROLLER_ADMIN_IP:/root/traffic.py



##################################### Run Shaker on Controller ################################################

#Runing local agent on controller
source /root/openrc
screen -dmS shaker-agent-screen shaker-agent --server-endpoint=127.0.0.1:18000 --agent-id=local_agent

#NODE_IP=${CONTROLLER_IP_ARRAY[0]}
echo "Run Shaker on Controller"

# Create remote dir.
REPORTS_DIR=`${SSH_CMD}$CONTROLLER_ADMIN_IP "mktemp -d"`
echo "Created reports dir name: " $REPORTS_DIR

# Create script for run on controller
REMOTE_SCRIPT=`${SSH_CMD}$CONTROLLER_ADMIN_IP "mktemp"`

echo "!!! -2- Running SSH_CMD"
${SSH_CMD}$CONTROLLER_ADMIN_IP "cat > ${REMOTE_SCRIPT}" <<EOF

source /root/openrc

#Creating policy limiter and getting ID
#neutron qos-policy-create limiter
#POLICY_ID=`neutron qos-policy-show limiter | grep '| id' | awk ' {print $4} '`

#Creating limit rule 30Mbs and getting ID
#RULE_ID=`neutron qos-bandwidth-limit-rule-create limiter --max-kbps 30000 | grep '| id' | awk ' {print $4} '`


#!/bin/bash -xe
SHAKER_PATH=${SHAKER_PATH}
TEST_SUBJECT=${TEST_SUBJECT:-networking}
REPORTS_DIR=`mktemp -d`
SERVER_ENDPOINT=$CONTROLLER_PUBLIC_IP
SERVER_PORT=18000
echo "SERVER_ENDPOINT: \$SERVER_ENDPOINT:\$SERVER_PORT"
#Fill in sources.list
printf 'deb http://ua.archive.ubuntu.com/ubuntu/ trusty universe' > /etc/apt/sources.list
##apt-get update
# Prepare environment
source /root/openrc
apt-get -y install python-dev libzmq-dev python-pip && pip install pbr pyshaker
#copy traffic.py to destination
#cp traffic.py /usr/local/lib/python2.7/dist-packages/shaker/engine/aggregators
iptables -I INPUT -s 10.20.0.0/16 -j ACCEPT
iptables -I INPUT -s 10.0.0.0/16 -j ACCEPT
iptables -I INPUT -s 172.16.0.0/16 -j ACCEPT
iptables -I INPUT -s 192.168.0.0/16 -j ACCEPT
shaker-image-builder --debug
echo "SERVER_ENDPOINT: \$SERVER_ENDPOINT:\$SERVER_PORT"
shaker --server-endpoint \$SERVER_ENDPOINT:\$SERVER_PORT --scenario /usr/local/lib/python2.7/dist-packages/shaker/scenarios/openstack/perf_l2.yaml --report my_HEAT_l2.html --debug
EOF

#Run script on remote node and get exit code
${SSH_CMD}$CONTROLLER_ADMIN_IP "bash -xe ${REMOTE_SCRIPT}"
