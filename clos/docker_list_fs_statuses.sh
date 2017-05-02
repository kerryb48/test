#!/bin/bash

set -o pipefail
if [ $# -ne 1 ]; then
  echo "Expected one parameters - filename containing the containers created by the companion script"
  exit 1
fi # if [ $# -ne 1 ]


container_record=$1
if [ -r "$container_record" ]; then
  IFS=","
  cat $container_record | while read cid name namespace ip; do
    echo -n "Instance: $name" 
    fs_status="$(sudo docker exec $name sh -c '/etc/init.d/flexswitch status')"
    echo "$fs_status" | grep --quiet "error"
    if [ $? -eq 0 ]; then
      echo " ERROR: Status is: $fs_status"
    else
      echo " OK: Status is: $fs_status"
    fi
  done
fi
