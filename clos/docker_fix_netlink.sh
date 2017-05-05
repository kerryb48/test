#!/bin/bash

set -o pipefail
set -u

src_namespace=$(sudo docker inspect -f '{{.State.Pid}}' $1)
src_int=$2
dest_namespace=$(sudo docker inspect -f '{{.State.Pid}}' $3)
dest_int=$4
echo "Trying to fix veth netlinks between $1:$2 and $3:$4"

# NOTE:
# The check fails due to permissions on /var/run/netns unless this script is
# run as root
if [ ! -e /var/run/netns/$src_namespace ]; then
  echo -e "\tNetwork NameSpace link from /proc to /var does not exist. Trying to fix:"
  sudo ln -vs /proc/$src_namespace/ns/net /var/run/netns/$src_namespace
else
  echo -e "\t/var/run/netns/$src_namespace exists. Proceeding"
fi #if [ ! -e /var/run/netns/$src_namespace ]

sudo ip link add ethSRC type veth peer name ethDEST
echo -e "\t\tMoving VETH endpoints into respective namespaces:"
echo -e "\t\t\tethSRC into namespace $src_namespace"
sudo ip link set ethSRC netns $src_namespace
echo -e "\t\t\tethDEST into namespace $dest_namespace"
sudo ip link set ethDEST netns $dest_namespace
echo -e "\t\tRenaming ethSRC to $src_int"
sudo ip -n $src_namespace link set ethSRC name $src_int
echo -e "\t\tRenaming ethDEST to $dest_int"
sudo ip -n $dest_namespace link set ethDEST name $dest_int
echo -e "\t\tBringing up SOURCE $src_int"
sudo ip -n $src_namespace link set $src_int up
echo -e "\t\tBringing up DEST $dest_int"
sudo ip -n $dest_namespace link set $dest_int up
