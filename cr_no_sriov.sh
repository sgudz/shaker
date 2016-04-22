#!/bin/bash

line="no"
echo "You can use 'sriov' option for creating sriov nets and ports"
echo -n "Would you like to create SRIOV ports and net? (yes/no): "
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
		SRIOV_NET_ID=`neutron net-create --provider:physical_network=$PHYSNET --provider:network_type=vlan --provider:segmentation_id=315 sriov-net | grep '| id' | awk '{print $4}'`
	else
		PHYSNET="physnet2"
		echo "Using default physnet \"$PHYSNET\" "
		SRIOV_NET_ID=`neutron net-create --provider:physical_network=$PHYSNET --provider:network_type=vlan --provider:segmentation_id=315 sriov-net | grep '| id' | awk '{print $4}'`
	fi
	echo -n "Enter subnet adress. Or it will create default subnet \"192.168.150.0/24\": "
	read SUBNET
	if [[ $SUBNET != '' ]]
	then
		echo "Your subnet is $SUBNET "
		SRIOV_SUBNET_ID=`neutron subnet-create $SRIOV_NET_ID $SUBNET --name sriov_subnet | grep '| id' | awk '{print $4}'`
	else
		SUBNET="192.168.150.0/24"
		echo "Using default subnet $SUBNET "
		SRIOV_SUBNET_ID=`neutron subnet-create $SRIOV_NET_ID $SUBNET --name sriov_subnet | grep '| id' | awk '{print $4}'`
		echo $SUBNET
	fi	
	FLOATING_ID=`neutron net-list | grep admin_floating_net | awk ' {print $2} '`
	ROUTER_ID=`neutron router-list | grep router04 | awk '{print $2}'`

	   #Attaching networks
	neutron router-interface-add $ROUTER_ID $SRIOV_SUBNET_ID

	   #Port creation
	SRIOV_PORT_ID_1=`neutron port-create $SRIOV_NET_ID --name sriov_port_1 --vnic-type direct | grep '| id' | awk ' {print $4} '`
	SRIOV_PORT_ID_2=`neutron port-create $SRIOV_NET_ID --name sriov_port_2 --vnic-type direct | grep '| id' | awk ' {print $4} '`
	IP_PORT_1=`neutron port-show $SRIOV_PORT_ID_1 | grep '| fixed_ips' | awk '{ print $7 }' | sed 's/\"//g' | sed 's/^\(.*\).$/\1/'`
	IP_PORT_2=`neutron port-show $SRIOV_PORT_ID_2 | grep '| fixed_ips' | awk '{ print $7 }' | sed 's/\"//g' | sed 's/^\(.*\).$/\1/'`

	   #Booting VMs in created ports
	nova boot --flavor m1.small --image Ubuntu_iperf_nload --nic port-id=$SRIOV_PORT_ID_1 sriov_instance_1 --key-name cloudKey
	nova boot --flavor m1.small --image Ubuntu_iperf_nload --nic port-id=$SRIOV_PORT_ID_2 sriov_instance_2 --key-name cloudKey
	FLOATING_IP_1=`nova floating-ip-create | grep '172.16.' | awk '{print $4}'`
	FLOATING_IP_2=`nova floating-ip-create | grep '172.16.' | awk '{print $4}'`
	echo " Subnet - $SUBNET"
	echo " $PHYSNET "
	sleep 1

	   #Associate floating
	nova floating-ip-associate sriov_instance_1 $FLOATING_IP_1
	nova floating-ip-associate sriov_instance_2 $FLOATING_IP_2

	   #netns params
	NETNS=`ip netns show | grep $SRIOV_NET_ID`
	ssh-keygen -f "/root/.ssh/known_hosts" -R $IP_PORT_1
	ssh-keygen -f "/root/.ssh/known_hosts" -R $IP_PORT_2
	echo $SSH_UB$IP_PORT_1
#	ssh -i cloud.key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@172.16.46.183 'nohup iperf3 -s  &> /dev/null &'
#	ssh -i cloud.key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@172.16.46.184 -t 'iperf3 -c 172.16.46.183 &> report_from_script.txt'
    echo "SRIOV"

elif [ $line == no ]
then 
	SSH_UB="ubuntu@"
		#Prepaire environment
	source /root/openrc
	NET_ID=`neutron net-create myNet01 | grep '| id' | awk '{print $4}'`
	echo -n "Enter subnet adress. For example \"192.168.150.0/24\": "
	read SUBNET
		if [[ $SUBNET != '' ]]
	then
		echo "Your subnet is $SUBNET "
		SUBNET_ID=`neutron subnet-create $NET_ID $SUBNET --name mySubnet01 | grep '| id' | awk '{print $4}'`
	else
		SUBNET="192.168.150.0/24"
		echo "Using default subnet $SUBNET "
		SUBNET_ID=`neutron subnet-create $NET_ID $SUBNET --name mySubnet01 | grep '| id' | awk '{print $4}'`
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
	nova boot --flavor m1.small --image Ubuntu_iperf_nload --nic port-id=$PORT_ID_1 instance_1 --key-name cloudKey
	nova boot --flavor m1.small --image Ubuntu_iperf_nload --nic port-id=$PORT_ID_2 instance_2 --key-name cloudKey
	FLOATING_IP_1=`nova floating-ip-create | grep '172.16.' | awk '{print $4}'`
	FLOATING_IP_2=`nova floating-ip-create | grep '172.16.' | awk '{print $4}'`
	sleep 1

	   #Associate floating
	nova floating-ip-associate instance_1 $FLOATING_IP_1
	nova floating-ip-associate instance_2 $FLOATING_IP_2

	   #netns params
	NETNS=`ip netns show | grep $NET_ID`
	ssh-keygen -f "/root/.ssh/known_hosts" -R $IP_PORT_1
	ssh-keygen -f "/root/.ssh/known_hosts" -R $IP_PORT_2
	echo $SSH_UB$IP_PORT_1
    echo "NO SRIOV"
#	ssh -i cloud.key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@172.16.46.183 'nohup iperf3 -s  &> /dev/null &'
#	ssh -i cloud.key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@172.16.46.184 -t 'iperf3 -c 172.16.46.183 &> report_from_script.txt'
else 
	echo "You didn't select anything. Launch again."
fi
