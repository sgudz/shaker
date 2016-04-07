#!/bin/bash -x
TIMES=$1
STOP="0"
while [ $TIMES != $STOP ]
do
 echo "$TIMES"
 NET_ARRAY=`neutron net-list | grep 10.0. | awk ' {print $7} '`
 SUB_IP=10.0.$(( RANDOM*256/32768 )).0/24
 echo $SUB_IP
 source /root/openrc
 NET_ID=`neutron net-create $$.myNet | grep '| id' | awk ' {print $4} '`
 SUBNET_ID=`neutron subnet-create $NET_ID $SUB_IP --name $$.mySubnet | grep '| id' | awk ' {print $4} '`
 ROUTER_ID=`neutron router-create $$.myRouter | grep '| id' | awk ' {print $4} '`
 FLOATING_ID=`neutron net-list | grep admin_floating_net | awk ' {print $2} '`
 neutron router-gateway-set $ROUTER_ID $FLOATING_ID
 neutron router-interface-add $ROUTER_ID $SUBNET_ID
 PORT_ID_1=`neutron port-create $NET_ID | grep '| id' | awk ' {print $4} '`
 IP_PORT_1=`neutron port-show $PORT_ID_1 | grep '| fixed_ips' | awk '{ print $7 }' | sed 's/\"//g' | sed 's/^\(.*\).$/\1/'`
 PORT_ID_2=`neutron port-create $NET_ID | grep '| id' | awk ' {print $4} '`
 IP_PORT_2=`neutron port-show $PORT_ID_2 | grep '| fixed_ips' | awk '{ print $7 }' | sed 's/\"//g' | sed 's/^\(.*\).$/\1/'`
 echo $IP_PORT_1
 echo $IP_PORT_2
# nova boot --flavor m1.small --image TestVM --nic port-id=$PORT_ID_1 $$.myInstance_1
# nova boot --flavor m1.small --image TestVM --nic port-id=$PORT_ID_2 $$.myInstance_2
 let TIMES=$[$TIMES-1]
done

