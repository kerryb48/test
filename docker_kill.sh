#!/bin/bash


if [ $# -ne 1 ]; then
  echo "Expected one parameters - filename containing the containers created by the companion script"
  exit 1
fi # if [ $# -ne 1 ]


container_record=$1
if [ -r "$container_record" ]; then
  IFS=","
  cat $container_record | while read cid name namespace ip; do
    echo "Container $name (id: $cid): "
    echo -en "\tDocker stop: "
    sudo docker stop $cid
    echo -en "\tDocker rm: "
    sudo docker rm $cid
    echo -e "\tip namespace ($namespace) cleanup."
    sudo ip netns delete $namespace
  done # while read cid name namespace
  unset IFS
else
  echo "ERROR: Could not read $container_record for processing."
  exit 1
fi
# Final cleanup piece
rm $container_record
