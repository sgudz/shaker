#!/bin/bash

source /root/openrc

RND=`cat /dev/urandom | tr -cd 'a-f0-9' | head -c 4`

echo -n "Will you use a keypair? By default it is \"No\". (yes/no): "
read ans
if [[ $ans != "" ]]
then
	if [[ $ans == yes ]]
	then
		echo -n "Create a new keypair? Defaults to \"No\". (yes/no): "
		read answer
		if [[ $answer == yes ]]
		then
			nova keypair-add $RND\_key > ~/.ssh/webserver_rsa
			export KEY_NAME=`nova keypair-list | grep $RND\_key | awk '{print $2}'`
			export KEY_FINGERPRINT=`nova keypair-list | grep $RND\_key | awk '{print $4}'`
			echo "Key name is - $KEY_NAME "
			echo "Fingerprint is - $KEY_FINGERPRINT "
			export CMD_ADD="--key-name $KEY_NAME"
		elif [[ $answer == no ]]
		then
			echo -n "Here is available Keys. Select one of them: "
			echo ""
			KEYS=`nova keypair-list | awk '{print $2}' | sed 's/Name//g'`
			for key in ${KEYS[@]}
			do
				echo "$key"
			done
			read to_use
			export KEY_NAME=$to_use
			export KEY_FINGERPRINT=`nova keypair-list | grep $to_use | awk '{print $4}'`
			echo "Using $KEY_NAME - $KEY_FINGERPRINT"
			export CMD_ADD="--key-name $KEY_NAME"
			fi
	else
		echo "Not using a Key pair...."
		export CMD_ADD=""
	fi
else
	echo "Not using a Key pair...."
	export CMD_ADD=""
fi


IMAGE_LIST=`nova image-list | grep ACTIVE | awk '{print $4}'`
FLOATING_ID=`neutron net-list | grep admin_floating_net | awk ' {print $2} '`
ROUTER_ID=`neutron router-list | grep router04 | awk '{print $2}'`
FLOATING_IP_1=`nova floating-ip-create | grep '172.16.' | awk '{print $4}'`
FLOATING_IP_2=`nova floating-ip-create | grep '172.16.' | awk '{print $4}'`

echo -n "Enter the name of image. Here is available images: "
for image in ${IMAGE_LIST[@]}
do
	echo ""
	echo " $image"
done
read IMAGE
echo "Using $IMAGE image. "
sleep 1

line="no"
echo "You can use 'SRIOV' option for creating sriov nets and ports."
echo -n "Create SRIOV ports and net? (yes/no): "
read line

if [ $line == yes ]
then
	SSH_UB="ubuntu@"

	   #Prepaire environment
	source /root/openrc
	echo -n "Enter physnet name. Or it will be set to default to \"physnet2\": "
	read PHYSNET
	if [[ $PHYSNET != '' ]]; then
		echo "Your physnet name is - \"$PHYSNET\" "
		SRIOV_NET_ID=`neutron net-create --provider:physical_network=$PHYSNET --provider:network_type=vlan $RND-sriov_net | grep '| id' | awk '{print $4}'`
	else
		PHYSNET="physnet2"
		echo "Using default physnet \"$PHYSNET\" "
		SRIOV_NET_ID=`neutron net-create --provider:physical_network=$PHYSNET --provider:network_type=vlan $RND-sriov_net | grep '| id' | awk '{print $4}'`
	fi
	echo -n "Enter subnet adress. Or it will create default subnet \"192.168.150.0/24\": "
	read SUBNET
	if [[ $SUBNET != '' ]]
	then
		echo "Your subnet is $SUBNET "
		SRIOV_SUBNET_ID=`neutron subnet-create $SRIOV_NET_ID $SUBNET --name $RND-sriov_subnet | grep '| id' | awk '{print $4}'`
	else
		SUBNET="192.168.150.0/24"
		echo "Using default subnet $SUBNET "
		SRIOV_SUBNET_ID=`neutron subnet-create $SRIOV_NET_ID $SUBNET --name $RND-sriov_subnet | grep '| id' | awk '{print $4}'`
		echo $SUBNET
	fi	

	   #Attaching networks
	neutron router-interface-add $ROUTER_ID $SRIOV_SUBNET_ID

	   #Port creation
	SRIOV_PORT_ID_1=`neutron port-create $SRIOV_NET_ID --name $RND-sriov_port_1 --vnic-type direct | grep '| id' | awk ' {print $4} '`
	SRIOV_PORT_ID_2=`neutron port-create $SRIOV_NET_ID --name $RND-sriov_port_2 --vnic-type direct | grep '| id' | awk ' {print $4} '`
	IP_PORT_1=`neutron port-show $SRIOV_PORT_ID_1 | grep '| fixed_ips' | awk '{ print $7 }' | sed 's/\"//g' | sed 's/^\(.*\).$/\1/'`
	IP_PORT_2=`neutron port-show $SRIOV_PORT_ID_2 | grep '| fixed_ips' | awk '{ print $7 }' | sed 's/\"//g' | sed 's/^\(.*\).$/\1/'`

	   #Booting VMs in created ports
	nova boot --flavor m1.small --image $IMAGE --nic port-id=$SRIOV_PORT_ID_1 $RND-sriov_instance_1 $CMD_ADD
	nova boot --flavor m1.small --image $IMAGE --nic port-id=$SRIOV_PORT_ID_2 $RND-sriov_instance_2 $CMD_ADD
	echo "Physnet name - $PHYSNET "
	echo "Net name - $RND-sriov_net, ID - $SRIOV_NET_ID"
	echo "$RND-sriov_instance_1 IP is: floating - $FLOATING_IP_1; internal - $IP_PORT_1"
	echo "$RND-sriov_instance_2 IP is: floating - $FLOATING_IP_2; internal - $IP_PORT_2"
	sleep 1

	   #Associate floating
	nova floating-ip-associate $RND-sriov_instance_1 $FLOATING_IP_1
	nova floating-ip-associate $RND-sriov_instance_2 $FLOATING_IP_2

	   #netns params
#	NETNS=`ip netns show | grep $SRIOV_NET_ID`
#	ssh-keygen -f "/root/.ssh/known_hosts" -R $IP_PORT_1
#	ssh-keygen -f "/root/.ssh/known_hosts" -R $IP_PORT_2
#	echo $SSH_UB$IP_PORT_1
#	ssh -i cloud.key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@172.16.46.183 'nohup iperf3 -s  &> /dev/null &'
#	ssh -i cloud.key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@172.16.46.184 -t 'iperf3 -c 172.16.46.183 &> report_from_script.txt'
    echo "SRIOV"

	#Creating No-SRIOV VMs
	
elif [ $line == no ]
then 
	SSH_UB="ubuntu@"
		#Prepaire environment
	source /root/openrc
	NET_ID=`neutron net-create $RND-myNet01 | grep '| id' | awk '{print $4}'`
	echo -n "Enter subnet adress. For example \"192.168.150.0/24\": "
	read SUBNET
		if [[ $SUBNET != '' ]]
	then
		echo "Your subnet is $SUBNET "
		SUBNET_ID=`neutron subnet-create $NET_ID $SUBNET --name $RND-mySubnet01 | grep '| id' | awk '{print $4}'`
	else
		SUBNET="192.168.150.0/24"
		echo "Using default subnet $SUBNET "
		SUBNET_ID=`neutron subnet-create $NET_ID $SUBNET --name $RND-mySubnet01 | grep '| id' | awk '{print $4}'`
	fi	
	FLOATING_ID=`neutron net-list | grep admin_floating_net | awk ' {print $2} '`
	ROUTER_ID=`neutron router-list | grep router04 | awk '{print $2}'`

	   #Attaching networks
	neutron router-interface-add $ROUTER_ID $SUBNET_ID

	   #Port creation
	PORT_ID_1=`neutron port-create $NET_ID --name port_1 | grep '| id' | awk ' {print $4} '`
	PORT_ID_2=`neutron port-create $NET_ID --name port_2 | grep '| id' | awk ' {print $4} '`
	IP_PORT_1=`neutron port-show $PORT_ID_1 | grep '| fixed_ips' | awk '{ print $7 }' | sed 's/\"//g' | sed 's/^\(.*\).$/\1/'`
	IP_PORT_2=`neutron port-show $PORT_ID_2 | grep '| fixed_ips' | awk '{ print $7 }' | sed 's/\"//g' | sed 's/^\(.*\).$/\1/'`

	   #Booting VMs in created ports
	nova boot --flavor m1.small --image $IMAGE --nic port-id=$PORT_ID_1 $RND-instance_1 $CMD_ADD
	nova boot --flavor m1.small --image $IMAGE --nic port-id=$PORT_ID_2 $RND-instance_2 $CMD_ADD
	echo "Physnet name - $PHYSNET "
	echo "Net name - $RND-myNet01, ID - $NET_ID"
	echo " $RND-instance_1 IP is: floating - $FLOATING_IP_1; internal - $IP_PORT_1"
	echo " $RND-instance_2 IP is: floating - $FLOATING_IP_2; internal - $IP_PORT_2"
	sleep 1

	   #Associate floating
	nova floating-ip-associate $RND-instance_1 $FLOATING_IP_1
	nova floating-ip-associate $RND-instance_2 $FLOATING_IP_2

	   #netns params
#	NETNS=`ip netns show | grep $NET_ID`
#	ssh-keygen -f "/root/.ssh/known_hosts" -R $IP_PORT_1
#	ssh-keygen -f "/root/.ssh/known_hosts" -R $IP_PORT_2
#	echo $SSH_UB$IP_PORT_1
    echo "NO SRIOV"
#	ssh -i cloud.key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@172.16.46.183 'nohup iperf3 -s  &> /dev/null &'
#	ssh -i cloud.key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@172.16.46.184 -t 'iperf3 -c 172.16.46.183 &> report_from_script.txt'
else 
	echo "You didn't select anything. Launch again."
fi
