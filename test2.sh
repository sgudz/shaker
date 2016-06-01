#!/bin/bash

neutron net-create net01
neutron subnet-create --name net01__subnet net01 10.1.1.0/24
neutron net-create net02
neutron subnet-create --name net02__subnet net02 10.1.2.0/24
neutron router-create router_01-02
neutron router-gateway-set router_01-02 admin_floating_net
neutron router-interface-add router_01-02 net01__subnet
neutron router-interface-add router_01-02 net02__subnet
NODE_1=node-2.domain.tld
NODE_2=node-7.domain.tld
NET_ID_1=`neutron net-list | awk '/net01/ {print $2}'`
NET_ID_2=`neutron net-list | awk '/net02/ {print $2}'`
neutron port-create $NET_ID_1 --binding:vnic-type macvtap --device_owner nova-compute --name sriov_1
neutron port-create $NET_ID_1 --name ovs_1
neutron port-create $NET_ID_1 --binding:vnic-type macvtap --device_owner nova-compute --name sriov_2
neutron port-create $NET_ID_1 --name ovs_2
neutron port-create $NET_ID_2 --binding:vnic-type macvtap --device_owner nova-compute --name sriov_3
neutron port-create $NET_ID_1 --name ovs_3
neutron port-create $NET_ID_2 --binding:vnic-type macvtap --device_owner nova-compute --name sriov_4
neutron port-create $NET_ID_1 --name ovs_4
port_id_s1=`neutron port-list | awk '/sriov_1/ {print $2}'`
port_id_o1=`neutron port-list | awk '/ovs_1/ {print $2}'`
port_id_s2=`neutron port-list | awk '/sriov_2/ {print $2}'`
port_id_o2=`neutron port-list | awk '/ovs_2/ {print $2}'`
port_id_s3=`neutron port-list | awk '/sriov_3/ {print $2}'`
port_id_o3=`neutron port-list | awk '/ovs_3/ {print $2}'`
port_id_s4=`neutron port-list | awk '/sriov_4/ {print $2}'`
port_id_o4=`neutron port-list | awk '/ovs_4/ {print $2}'`
nova boot vm1 --flavor m1.small --image ubuntu_14.04 --availability-zone nova:$NODE_1 --nic port-id=$port_id_s1 --nic port-id=$port_id_o1 --key-name cloudkey
nova boot vm2 --flavor m1.small --image ubuntu_14.04 --availability-zone nova:$NODE_1 --nic port-id=$port_id_s2 --nic port-id=$port_id_o2 --key-name cloudkey
nova boot vm3 --flavor m1.small --image ubuntu_14.04 --availability-zone nova:$NODE_1 --nic port-id=$port_id_s3 --nic port-id=$port_id_o3 --key-name cloudkey
nova boot vm4 --flavor m1.small --image ubuntu_14.04 --availability-zone nova:$NODE_2 --nic port-id=$port_id_s4 --nic port-id=$port_id_o4 --key-name cloudkey
