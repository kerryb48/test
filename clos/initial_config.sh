#!/bin/bash
# spine4,eth1,core2,eth1
# spine4,eth2,core1,eth1
# spine3,eth1,core2,eth2
#b7e89891af16c64599e05a31d5e0161ed0cfbe71df34bf316993e9ddb1eea926,core1,21629,172.17.0.2
#2f772b7d8b9e91396334ec6cd32f6e677928ba24b24f09109c9e416fd3c7b33d,core2,21796,172.17.0.3
#5491649ff892284be536ebf7fa6cc016839b2a81bc2e4b0b1e5de8bbf7d54b59,spine1,21971,172.17.0.4

IFS=","
echo "BGPGlobal settings"
cat containers.lst | while read cid name ns ip; do
  echo "flex --host $ip BGPGlobal config PATCH --json_blob '{\"ASNum\":\"$ns\",\"RouterId\":\"$ip\", \"Disabled\":false}'"
done

echo "LLDPGlobal settings"
cat containers.lst | while read cid name ns ip; do
  echo "flex --host $ip LLDPGlobal config PATCH --json_blob '{\"Enable\": true}'"
done

echo "Per-port description"
sort -t "," -k1 netlinks | while read src srcnic dst dstnic; do 
  grep "$src" containers.lst | while read cid name ns ip; do
    echo "flex --host $ip Port config PATCH --json_blob '{\"Description\":\"$src:$srcnic to $dst:$dstnic\", \"IntfRef\":\"$srcnic\"}'"

    #echo "flex --host $name Port config PATCH --json_blob '{\"Description\":\"$src:$srcnic to $dst:$dstnic\", \"IntfRef\":\"$srcnic\"}'"
  done
done
sort -t "," -k3 netlinks | while read src srcnic dst dstnic; do 
  grep "$dst" containers.lst | while read cid name ns ip; do
    echo "flex --host $ip Port config PATCH --json_blob '{\"Description\":\"$dst:$dstnic to $src:$srcnic\", \"IntfRef\":\"$dstnic\"}'"
    #echo "flex --host $name Port config PATCH --json_blob '{\"Description\":\"$dst:$dstnic to $src:$srcnic\", \"IntfRef\":\"$dstnic\"}'"
  done
done

# Currently disabled since it seems that the global LLDP enable also auto-sets these.
# Phil feels that automatic enablement is not quite what we want, so at some point, these will be necessary
echo "Per-port LLDP"
sort -t "," -k1 netlinks | while read src srcnic dst dstnic; do 
  grep "$src" containers.lst | while read cid name ns ip; do
    echo "flex --host $ip LLDPIntf config PATCH --json_blob '{\"Enable\":true, \"IntfRef\":\"$srcnic\"}'"

    #echo "flex --host $name Port config PATCH --json_blob '{\"Description\":\"$src:$srcnic to $dst:$dstnic\", \"IntfRef\":\"$srcnic\"}'"
  done
done
sort -t "," -k3 netlinks | while read src srcnic dst dstnic; do 
  grep "$dst" containers.lst | while read cid name ns ip; do
    echo "flex --host $ip LLDPIntf config PATCH --json_blob '{\"Enable\":true, \"IntfRef\":\"$dstnic\"}'"
    #echo "flex --host $name Port config PATCH --json_blob '{\"Description\":\"$dst:$dstnic to $src:$srcnic\", \"IntfRef\":\"$dstnic\"}'"
  done
done

unset IFS 
