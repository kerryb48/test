#!/bin/bash

set -o pipefail
set -u

if [ $# -ne 4 ]; then
  echo "Expected usage: $0 dockerinst1 srcNIC dockerinst2 dstNIC"
  echo "Example: $0 flexswitch1 fpPort20 flexswitch2 fpPort7"
  exit 1
fi
src_namespace=$(sudo docker inspect -f '{{.State.Pid}}' $1)
src_int=$2
# Check to see if the source NIC already exists in the container's namespace
sudo ip -o -n $src_namespace link | grep -q "$src_int@"
if [ $? -eq 0 ]; then
  echo "ERROR: Source container $1 ($src_namespace) already contains $src_int:"
  sudo ip -o -n $src_namespace link | grep "$src_int@"
  exit 1
fi # if [ $? -ne 0 ]
dest_namespace=$(sudo docker inspect -f '{{.State.Pid}}' $3)
dest_int=$4
# Check to see if the destination NIC already exists in the container's namespace
sudo ip -o -n $dest_namespace link | grep -q "$dest_int@"
if [ $? -eq 0 ]; then
  echo "ERROR: Destination container $1 ($dest_namespace) already contains $dest_int:"
  sudo ip -o -n $dest_namespace link | grep -q "$dest_int@"
  exit 1
fi # if [ $? -ne 0 ]
echo "Trying to connect VETH netlinks between $1:$2 and $3:$4"

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
