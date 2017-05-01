#!/bin/bash
#
# Version 0.2
#

#
# Lets be pessimistic
# 
# A command failing during a pipe will cause the whole pile to fail.
set -o pipefail
# Uninitalized variables' use should cause errors
set -u

#
# Create the /var/run/netns for the further trickery with 'ip netns'
#
sudo mkdir -p /var/run/netns
# Initial variables
self=$0
cores=2
spines=4
spine_groups=2
leaf=8
fl_containers=0
hosts=0
dry_run=0
declare -A a_cores
declare -A a_spines
declare -A a_leaves
container_record="containers.lst"
netlinks="netlinks"

#Set colours/text styles
NORM=$(tput sgr0)
BOLD=$(tput bold)
REV=$(tput smso)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)

#Help function
function display_help {
  echo -e "${YELLOW}NOTE: ${NORM} This version does not, yet, do anything with most of these. Sorry about that."
  echo -e \\n"Help documentation for ${BOLD}${self}.${NORM}"\\n
  echo "Command line switches are optional. The following switches are recognized."
  echo "${REV}-s${NORM} Specifies the number of ${BOLD}core${NORM}. Default is ${BOLD}$cores${NORM}."
  echo "${REV}-l${NORM} Specifies the number of ${BOLD}spines${NORM}. Default is ${BOLD}$spines${NORM}."
  echo "${REV}-g${NORM} Specifies the width of ${BOLD}spines group${NORM}. Default is ${BOLD}$spine_groups${NORM}."
  echo "${REV}-t${NORM} Specifies the number of ${BOLD}leaf${NORM}. Default is ${BOLD}$leaf${NORM}."
  echo "${REV}-f${NORM} Specifies the filename in which the created containers will be recorded. Default is ${BOLD}$container_record${NORM}."
  echo "${REV}-z${NORM} Specifies the number of ${BOLD}hosts${NORM}. Default is ${BOLD}$hosts${NORM}."
  echo "${REV}-d${NORM} Do a ${BOLD}dry run${NORM}. Print what would be done, but not actually do anything"
  echo -e "${REV}-h${NORM} Displays this help message. No further functions are performed."\\n
  echo -e "Example: ${BOLD}$self -s 2 -l 4 -t 8 -g 2 -z 0 ${NORM}"\\n
  exit 0
}


#
# TODO: Actually accept these parameters on the command line...
# For now, these are ignored, because I've not figured out a good algorithm to do the spine-group/leaf-group bits.
# A better coder than I can do this, I suspect.
optspec=":s:l:t:z:g:f:hd"
while getopts "$optspec" optchar; do
  case $optchar in
    s)
      #cores=$OPTARG
      echo "${REV}Cores${NORM} set to: ${BOLD}$cores${NORM}" >&2
      ;;
    l)
      #spines=$OPTARG
      echo "${REV}Spines${NORM} set to: ${BOLD}$spines${NORM}" >&2
      ;;
    g)
      #spine_groups=$OPTARG
      echo "${REV}Spine Groups${NORM} set to: ${BOLD}$spine_groups${NORM}" >&2
      ;;
    t)
      #leaf=$OPTARG
      echo "${REV}Leaves${NORM} set to ${BOLD}$leaf${NORM}" >&2
      ;;
    z)
      #hosts=$OPTARG
      echo "${REV}Hosts${NORM} set to ${BOLD}$hosts${NORM}" >&2
      ;;
    f)
      container_record=$OPTARG
      echo "Container record ${REV}filename${NORM} is set to: ${BOLD}$container_record${NORM}" >&2
      ;;
    d)
      dry_run=1
      echo "${BOLD}Dry Run ${NORM} mode. ${BOLD}No changes will be made${NORM}" >&2
      ;;
    h)
      display_help
      exit 0
      ;;
    :)
      echo "Option ${REV}-$OPTARG${NORM} requires an argument." >&2
      exit 1
      ;;
    \?)
      echo "Invalid option seen: \"-$OPTARG\"" >&2
      ;;
  esac
done

#Check the number of arguments. If none are passed, print help and exit.
NUMARGS=$#
#echo -e \\n"Number of arguments: $NUMARGS"
if [ $NUMARGS -eq 0 ]; then
  echo "Running with defaults..."
fi # if [ $NUMARGS -eq 0 ]

if [ -e "$container_record" ]; then
  echo "${RED}ERROR: ${NORM}Output filename $container_record already exists"
  echo "Cowardly refusing to continue"
  exit 1
else
  if [ $dry_run -eq 0 ]; then 
    touch $container_record
  fi # if [ $dry_run -eq 1 ]
  if [ $? -ne 0 ]; then
    echo "${RED}ERROR: ${NORM} Container record file ${container_record} does not appear writeable"
    exit 1
  fi # if [ $? -ne 0 ]
fi # if [ -e "$container_record" ]

echo "***** Checkout the flexswitch base image *******"
if [ $dry_run -eq 1 ]; then 
  echo "${REV}DRY-RUN: ${NORM}sudo docker pull snapos/flex:latest"
else 
  sudo docker pull snapos/flex:latest
  if [ $? -ne 0 ]; then
	  echo "${RED}ERROR:${NORM} Docker pull failed. Please check output above and fix" 1>&2
	  exit 1
  fi # if [ $? -ne 0 ]
fi

echo -e "\n\n"

fl_containers=$(($cores+$leaf+$spines))
total_containers=$(($fl_containers+$hosts))
leaves_per_group=$(echo "scale=0;($leaf)/$spine_groups"|bc)
# Some overall output:
echo "${BOLD}Work to be peformed:${NORM}"
echo "${REV}FlexSwitch${NORM} containers: $fl_containers ($cores core, $spines spines in $spine_groups groups, $leaf leaves with $leaves_per_group per spine group)" 
echo "${REV}Host${NORM} containers: $hosts"
echo "${REV}Record${NORM} is being kept in ${BOLD}$container_record${NORM}"

#
# 
#
function docker_start_core {
  if [ ! -z "$1" ]; then
    instance="$1"
  fi # if [ ! -z "$1" ]; then
  if [ $dry_run -eq 1 ]; then
    echo "${REV}DRY-RUN: ${NORM}"
    echo -e "\tStarting a docker container type: ${REV}FlexSwitch Core${NORM}, instance name: ${BOLD}core$instance${NORM}"
  else
    echo -e "\tStarting a docker container type: ${REV}FlexSwitch Core${NORM}, instance name: ${BOLD}core$instance${NORM}"
  container_id=$(sudo docker run -dt --log-driver=syslog --privileged --cap-add ALL --hostname=core$instance --name core$instance -P snapos/flex:latest)
    if [ $? -ne 0 ]; then
      echo "${RED}ERROR:${NORM} Failed starting docker instance \"$instance\". Please check output above and fix" 1>&2
      exit 1
    else
      echo -n "$container_id," >> $container_record
    fi # if [ $? -ne 0 ]
  fi # if [ $dry_run -eq 1 ]
  return 0
}

function docker_start_spine {
  if [ ! -z "$1" ]; then
    instance="$1"
  fi # if [ ! -z "$1" ]; then
  if [ $dry_run -eq 1 ]; then
    echo "${REV}DRY-RUN: ${NORM}"
    echo -e "\tStarting a docker container type: ${REV}FlexSwitch Spine${NORM}, instance name: ${BOLD}spine$instance${NORM}"
  else
    echo -e "\tStarting a docker container type: ${REV}FlexSwitch Spine${NORM}, instance name: ${BOLD}spine$instance${NORM}"
    container_id=$(sudo docker run -dt --log-driver=syslog --privileged --cap-add ALL --hostname=spine$instance --name spine$instance -P snapos/flex:latest)
    if [ $? -ne 0 ]; then
      echo "${RED}ERROR:${NORM} Failed starting docker instance \"$instance\". Please check output above and fix" 1>&2
      exit 1
    else
      echo -n "$container_id," >> $container_record
    fi # if [ $? -ne 0 ]
  fi # if [ $dry_run -eq 1 ]
  return 0
}

function docker_start_leaf {
  if [ ! -z "$1" ]; then
    instance="$1"
  fi # if [ ! -z "$1" ]; then
  if [ $dry_run -eq 1 ]; then
    echo "${REV}DRY-RUN: ${NORM}"
    echo -e "\tStarting a docker container type: ${REV}FlexSwitch Leaf${NORM}, instance name: ${BOLD}leaf$instance${NORM}"
  else
    echo -e "\tStarting a docker container type: ${REV}FlexSwitch Leaf${NORM}, instance name: ${BOLD}leaf$instance${NORM}"
    container_id=$(sudo docker run -dt --log-driver=syslog --privileged --cap-add ALL --hostname=leaf$instance --name leaf$instance -P snapos/flex:latest)
    if [ $? -ne 0 ]; then
      echo "${RED}ERROR:${NORM} Failed starting docker instance \"$instance\". Please check output above and fix" 1>&2
      exit 1
    else
      echo -n "$container_id," >> $container_record
    fi # if [ $? -ne 0 ]
  fi # if [ $dry_run -eq 1 ]
  return 0
}

function docker_start_host {
  if [ ! -z "$1" ]; then
    instance="$1"
  fi # if [ ! -z "$1" ]; then
  if [ $dry_run -eq 1 ]; then
    echo "${REV}DRY-RUN: ${NORM}"
    echo -e "\tStarting a docker container type: ${REV}Host${NORM}, instance name: ${BOLD}host$instance${NORM}"
  else
    echo -e "\tStarting a docker container type: ${REV}Host${NORM}, instance name: ${BOLD}host$instance${NORM}"
    container_id=$(sudo docker run -dt --log-driver=syslog --hostname=host$instance --name host$instance -P snapos/flex:latest)
    if [ $? -ne 0 ]; then
      echo "${RED}ERROR${NORM}Failed starting docker instance \"$instance\". Please check output above and fix" 1>&2
      exit 1
    else
      echo -n "$container_id," >> $container_record
    fi # if [ $? -ne 0 ]
  fi # if [ $dry_run -eq 1 ]
  return 0
}

if [ $cores -ne 0 ]; then
  for ((i=1; i<=$cores; i++))
  do
    echo "Core number: $i"
    docker_start_core $i
    if [ $dry_run -eq 1 ]; then
      echo "${REV}DRY-RUN: ${NORM}"
    else
      namespace=$(sudo docker inspect -f '{{.State.Pid}}' core$i)
      mgmt_ip=$(sudo docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' core$i)
      echo "core$i,$namespace,$mgmt_ip" >> $container_record
      echo -en "\t"; sudo ln -vs /proc/$namespace/ns/net /var/run/netns/$namespace
      a_cores["core$i"]="$namespace"
  fi # if [ $dry_run -eq 1 ]
  done
fi # if [ $cores -ne 0 ]; then

if [ $spines -ne 0 ]; then
  for ((i=1; i<=$spines; i++))
  do
    echo "Spine number: $i"
    docker_start_spine $i
    if [ $dry_run -eq 1 ]; then
      echo "${REV}DRY-RUN: ${NORM}"
    else
      namespace=$(sudo docker inspect -f '{{.State.Pid}}' spine$i)
      mgmt_ip=$(sudo docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' spine$i)
      echo -en "\t"; sudo ln -vs /proc/$namespace/ns/net /var/run/netns/$namespace
      echo "spine$i,$namespace,$mgmt_ip" >> $container_record
      a_spines["spine$i"]="$namespace"
    fi # if [ $dry_run -eq 1 ]
  done
fi # if [ $spines -ne 0 ]; then

if [ $leaf -ne 0 ]; then
  for ((i=1; i<=$leaf; i++))
  do
    echo "Leaf number: $i"
    if [ $dry_run -eq 1 ]; then
      echo "${REV}DRY-RUN: ${NORM}"
    else
      docker_start_leaf $i
      namespace=$(sudo docker inspect -f '{{.State.Pid}}' leaf$i)
      mgmt_ip=$(sudo docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' leaf$i)
      echo -en "\t"; sudo ln -vs /proc/$namespace/ns/net /var/run/netns/$namespace
      echo "leaf$i,$namespace,$mgmt_ip" >> $container_record
      a_leaves["leaf$i"]="$namespace"
    fi # if [ $dry_run -eq 1 ]
  done
fi # if [ $leaf -ne 0 ]; then

if [ $hosts -ne 0 ]; then
  for ((i=1; i<=$hosts; i++))
  do
    echo "HOST number: $i"
    docker_start_host $i
    if [ $dry_run -eq 1 ]; then
      echo "${REV}DRY-RUN: ${NORM}"
    else
      namespace=$(sudo docker inspect -f '{{.State.Pid}}' host$i)
      mgmt_ip=$(sudo docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' host$i)
      sudo ln -vs /proc/$namespace/ns/net /var/run/netns/$namespace
      echo "host$i,$namespace,$mgmt_ip" >> $container_record
    fi # if [ $dry_run -eq 1 ]
  done
fi # if [ $leaf -ne 0 ]; then

#set -x
echo "All cores and spines:"
#
# This function expects one parameter - the Docker namespace, into which it will attempt to delve
# and suss out the next ethX number to make, and then return that number
#

function next_int {
  namespace=$1
  lastint=$(sudo ip -o -n $namespace link | grep -vE "lo: |ethSRC|ethDEST" | grep "eth" |awk '{print $2}'|awk -F "@" '{print $1}'|sort|tail -1|sed 's/eth//')
  let nextint=lastint+1
  echo $nextint
}

#
# This function creates a veth pair between two named docker spaces
#
function make_veth {
  src_namespace=$1
  dest_namespace=$2
  sudo ip link add ethSRC type veth peer name ethDEST
  echo -e "\t\tMoving VETH endpoints into respective namespaces:"
  echo -e "\t\t\tethSRC into namespace $src_namespace"
  sudo ip link set ethSRC netns $src_namespace
  echo -e "\t\t\tethDEST into namespace $dest_namespace"
  sudo ip link set ethDEST netns $dest_namespace
  src_int=$(next_int $src_namespace)
  dest_int=$(next_int $dest_namespace)
  echo -e "\t\tRenaming ethSRC to eth$src_int"
  sudo ip -n $src_namespace link set ethSRC name eth$src_int
  echo -e "\t\tRenaming ethDEST to eth$dest_int"
  sudo ip -n $dest_namespace link set ethDEST name eth$dest_int
  echo -e "\t\tBringing up SOURCE eth$src_int"
  sudo ip -n $src_namespace link set eth$src_int up
  echo -e "\t\tBringing up DEST eth$dest_int"
  sudo ip -n $dest_namespace link set eth$dest_int up
  echo "$src_namespace,eth$src_int,$dest_namespace,eth$dest_int" >> $netlinks
}

for spine_key in "${!a_spines[@]}"; do
  spine_namespace=${a_spines[$spine_key]}
  echo -e "Spine: \"$spine_key\", namespace: \"$spine_namespace\"";
  for core_key in "${!a_cores[@]}"; do
    core_namespace=${a_cores[$core_key]}
    echo -e "\tCore: \"$core_key\", namespace: \"$core_namespace\"";
    echo -e "\t\tCreating VETH interface between spine $spine_key and core $core_key"
    if [ $dry_run -eq 1 ]; then
      echo "${REV}DRY-RUN: ${NORM}"
    else
      make_veth $spine_namespace $core_namespace
    fi # if [ $dry_run -eq 1 ]
#    for key in "${!a_leaves[@]}"; do
#      echo -e "\t\tLeaf: \"$key\", namespace: \"${a_leaves[$key]}\"";
#    done
  done # 
done #

#
# Walk the spines and put things into groups
#
group1_spines="1 2"
group1_leaves="1 2 3 4"
group2_spines="3 4"
group2_leaves="5 6 7 8"

# Commented out as a starting point for doing algorithmic splitting of spines
# into groups
#keys=(${!a_spines[@]})
#for (( index=0; $index < ${#a_spines[@]}; index+=1 )); do
#  key=${keys[$index]};
#  group=$(echo "scale=0;$index/$spine_groups+1"|bc)
#  echo $key -- ${a_spines[$key]} $group
#done
echo "Processing Spine/Leaf groups:"
if [ $dry_run -eq 1 ]; then
  echo "${REV}DRY-RUN${NORM}"
else
  echo "Group 1:"
  for leaf in $group1_leaves; do
    for spine in $group1_spines; do
      spine_namespace=${a_spines[spine$spine]}
      leaf_namespace=${a_leaves[leaf$leaf]}
      #echo "Leaf ${a_leaves[leaf$leaf]} -> Spine ${a_spines[spine$spine]}"
      echo -e "\tSpine (spine$spine, namespace:$spine_namespace) -> Leaf (leaf$leaf, namespace: $leaf_namespace)"
      make_veth $leaf_namespace $spine_namespace
    done
  done
fi # if [ $dry_run -eq 1 ]

echo "Group 2:"
if [ $dry_run -eq 1 ]; then
  echo "${REV}DRY-RUN${NORM}"
else
  for leaf in $group2_leaves; do
    for spine in $group2_spines; do
      spine_namespace=${a_spines[spine$spine]}
      leaf_namespace=${a_leaves[leaf$leaf]}
      #echo "Leaf ${a_leaves[leaf$leaf]} -> Spine ${a_spines[spine$spine]}"
      echo -e "\tSpine (spine$spine, namespace:$spine_namespace) -> Leaf (leaf$leaf, namespace: $leaf_namespace)"
      make_veth $leaf_namespace $spine_namespace
      echo
    done
  done
fi # if [ $dry_run -eq 1 ]

echo -e "Start flexswtich to pick up the interfaces "
if [ $dry_run -eq 1 ]; then
  echo "${REV}DRY-RUN${NORM}"
else
  for instance in $(sudo docker ps | awk '{print $NF}'|grep -v "NAME"); do
    echo "##############################"
    echo "#######\"$instance\" FS restart######"
    echo "##############################"
    sudo docker exec $instance sh -c "/etc/init.d/flexswitch restart" 
    if [ $? -ne 0 ]; then
       echo "${RED}ERROR: ${NORM}Starting a flexswitch process in docker instance \"$instance\" failed. Please check output above and fix" 1>&2
       exit 1
    fi # if [ $? -ne 0 ]
    echo "Sleeping 20s to allow for the FlexSwitch daemons to start"
    sleep 20
done
fi # if [ $dry_run -eq 1 ]

if [ $dry_run -eq 1 ]; then
  echo "Checking on the status of FlexSwitch in docker instance \"$instance\"..."
  echo "${REV}DRY-RUN${NORM}"
else
  for instance in $(sudo docker ps | awk '{print $NF}'|grep -v "NAME"); do
    echo "Checking on the status of FlexSwitch in docker instance \"$instance\"..."
    sudo docker exec $instance sh -c "/etc/init.d/flexswitch status"
    if [ $? -ne 0 ]; then
       echo "${RED}ERROR: ${NORM}Checking a flexswitch process in docker instance \"$instance\" failed. Please check output above and fix" 1>&2
       exit 1
    fi # if [ $? -ne 0 ]
  done
fi # if [ $dry_run -eq 1 ]

echo "Network Links:"
if [ $dry_run -eq 1 ]; then
  echo "${REV}DRY-RUN${NORM}"
else
  IFS=","
  cat $container_record | while read cid name namespace ip; do 
    sed -i "s/$namespace/$name/g" $netlinks 
  done
  unset IFS
  sort netlinks
fi # if [ $dry_run -eq 1 ]

echo "Containers:"
if [ $dry_run -eq 1 ]; then
  echo "${REV}DRY-RUN${NORM}"
else
  cat $container_record
fi # if [ $dry_run -eq 1 ]
