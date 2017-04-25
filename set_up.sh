for item in $nodes; do
  ifaces=`ssh -q $item ip link list | grep " en" | awk '{print $2}' | sed 's/\://g'`
for int in $ifaces;do
ssh -q $item ip link set up dev $int
echo "Setting up $int"
  done
done
