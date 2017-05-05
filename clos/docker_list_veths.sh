#/bin/bash
declare -A nics

function add_to_nics {
    nics[$1]="$3 $2"
}

sudo mkdir -p /var/run/netns

if [ -z $1 ]; then
  for instance in $(sudo docker ps | awk '{print $NF}'|grep -v "NAME"); do
    inst_namespace=$(sudo docker inspect -f '{{.State.Pid}}' $instance)
    #echo "Instance: $instance (ns: $inst_namespace)"
    #echo -en "\t"; sudo ln -vs /proc/$inst_namespace/ns/net /var/run/netns/$inst_namespace
    while read id ethtupple; do
      add_to_nics $id $ethtupple $instance
      eth=$(echo $ethtupple | awk -F"@" '{print $1}')
      ethlink=$(echo $ethtupple | awk -F"@" '{print $2}')
      #echo -e "\teth: $eth, ethlink: $ethlink (ID: $id)"
    # eth0 is a valid NIC, but it is also the default Docker NIC, so it's not likely to be a veth
    done <<< "$(sudo ip -o -n $inst_namespace link | grep fpPanel| sed 's/://g' | awk '{print $1" "$2}')"
    #echo ""
  done
else
    for instance in "$@"; do
    inst_namespace=$(sudo docker inspect -f '{{.State.Pid}}' $instance)
    #echo "Instance: $instance (ns: $inst_namespace)"
    # Normally, I'd just pipe this output into a 'while read' loop, but those
    # are subshells in bash, which gets into variable scoping issues.
    # So, instead, brute-forcing it with variables-a-plenty.
    while read id ethtupple; do
      add_to_nics $id $ethtupple $instance
      eth=$(echo $ethtupple | awk -F"@" '{print $1}')
      ethlink=$(echo $ethtupple | awk -F"@" '{print $2}')
      #echo -e "\teth: $eth, ethlink: $ethlink (ID: $id)"
    # eth0 is a valid NIC, but it is also the default Docker NIC, so it's not likely to be a veth
    done <<< "$(sudo ip -o -n $inst_namespace link | grep fpPanel| sed 's/://g' | awk '{print $1" "$2}')"
    #echo ""
    done # for instance in "$@"
fi # if [ -z $1 ]; then

#echo "Printing nics: (total: ${#nics[@]})"
for key in "${!nics[@]}"; do
  echo -n "${nics[$key]}"
  #echo -n "nic's KEY: $key, value: ${nics[$key]}"
  vethpair=$(echo ${nics[$key]} | awk -F"@" '{print $NF}' | sed 's/if//')
  if [ ! -z $vethpair ]; then
    echo " <-> ${nics[$vethpair]}"
  else
    echo ""
  fi # if [ ! -z $vethpair ]
done

