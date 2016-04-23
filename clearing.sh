INSTANCE_LIST=`nova list | grep instance_ | awk '{print $2}'`
for image in ${INSTANCE_LIST[@]}
do
  nova delete $image
done

FLOATING_LIST=`neutron floatingip-list | grep 172.16 | awk '{print $2}'`
for ip in ${FLOATING_LIST[@]}
do
  neutron floatingip-delete $ip
done

SUBNET_LIST=`neutron subnet-list | grep mySubnet | awk '{print $4}'`
ROUTER_ID=`neutron router-list | grep router | awk '{print $2}'`
ROUTER_NAME=`neutron router-list | grep router | awk '{print $4}'`
for subnet in ${SUBNET_LIST[@]}
do
  neutron router-interface-delete $ROUTER_ID $subnet
done

PORTS_LIST=`neutron port-list | grep port_ | awk '{print $2}'`
for port in ${PORTS_LIST[@]}
do
  neutron port-delete $port
done

NET_LIST=`neutron net-list | grep myNet | awk '{print $2}'`
for net in ${NET_LIST[@]}
do
  neutron net-delete $net
done
