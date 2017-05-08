#!/bin/bash
set -o pipefail

if [ $# -ne 1 ]; then
  echo "Expected one parameters - filename containing the netlinks created by the companion script"
  exit 1
fi # if [ $# -ne 1 ]

cat $1 | sed 's/,/ /g' | while read srcinst srcnic dstinst dstnic; do
  echo -n "Checking link from $srcinst:$srcnic to $dstinst:$dstnic: "
  ./docker_list_veths.sh $srcinst $dstinst|grep "^$srcinst $srcnic"|grep --quiet "$dstinst $dstnic"
  if [ $? -eq 0 ]; then
    echo "Link OK"
  else
    echo "Link NOT OK"
    echo "Try running \"docker_make_netlink.sh $srcinst $srcnic $dstinst $dstnic\" to fix"
  fi
done
