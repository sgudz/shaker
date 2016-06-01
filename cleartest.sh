INSTANCE_LIST=`nova list | grep vm | awk '{print $2}'`
for image in ${INSTANCE_LIST[@]}
do
  nova delete $image
done

FLOATING_LIST=`neutron floatingip-list | grep 172.16 | awk '{print $2}'`
for ip in ${FLOATING_LIST[@]}
do
  neutron floatingip-delete $ip
done

SUBNET_LIST=`neutron subnet-list | grep net0 | awk '{print $4}'`
ROUTER_ID=`neutron router-list | grep router_01-02 | awk '{print $2}'`
ROUTER_NAME=`neutron router-list | grep router_01-02 | awk '{print $4}'`
for subnet in ${SUBNET_LIST[@]}
do
  neutron router-interface-delete $ROUTER_ID $subnet
  neutron router-gateway-clear $ROUTER_ID
  neutron router-delete $ROUTER_ID
done

PORTS_LIST=`neutron port-list | grep sriov | awk '{print $2}'`
for port in ${PORTS_LIST[@]}
do
  neutron port-delete $port
done

PORTS_LIST2=`neutron port-list | grep ovs | awk '{print $2}'`
for port2 in ${PORTS_LIST2[@]}
do
  neutron port-delete $port2
done


NET_LIST=`neutron net-list | grep net0 | awk '{print $2}'`
for net in ${NET_LIST[@]}
do
  neutron net-delete $net
done
