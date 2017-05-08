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
OS="$(uname)"
case $OS in
  'Linux')
    OS='Linux'
    echo "**** Start the docker script *****"
    ;;
  *)
    echo "The underlying Operating System is not Linux. Docker with flexswitch is not supported."
    echo "FlexSwitch in Docker relies on VETH interface magic which isn't found outside Linux."
    echo " Exiting......"
    exit 1
    ;;
esac

#
# Create the /var/run/netns for the further trickery with 'ip netns'
#
sudo mkdir -p /var/run/netns
# Initial variables
self=$0
docker=2
links=1
hosts=0
dry_run=0
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
  echo -e \\n"Help documentation for ${BOLD}${self}.${NORM}"\\n
  echo "Command line switches are optional. The following switches are recognized:"
  echo "${REV}-f${NORM} Specifies the filename in which the created containers will be recorded. Default is ${BOLD}$container_record${NORM}."
  echo "${REV}-z${NORM} Specifies the number of ${BOLD}hosts${NORM}. Default is ${BOLD}$hosts${NORM}."
  echo "${REV}-l${NORM} Specifies the number of ${BOLD}links${NORM} between the two containers. Default is ${BOLD}$links${NORM}."
  echo "${REV}-d${NORM} Do a ${BOLD}dry run${NORM}. Print what would be done, but not actually do anything"
  echo -e "${REV}-h${NORM} Displays this help message. No further functions are performed."\\n
  echo -e "Example: ${BOLD}$self -s 2 -z 0 ${NORM}"\\n
  exit 0
}


optspec=":s:l:z:f:hd"
while getopts "$optspec" optchar; do
  case $optchar in
    s)
      docker=$OPTARG
      echo "${REV}Cores${NORM} set to: ${BOLD}$cores${NORM}" >&2
      ;;
    z)
      hosts=$OPTARG
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
    l)
      links=$OPTARG
      echo "The two FlexSwitch containers will have${BOLD}$links${NORM} established between them." >&2
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

function fancy_sleep {
  # It isn't fun to just sit and watch a prompt during a sleep command
  # wondering if something's wedged.
  # So, a bit of a progress display
  #
    sleeptime="$1"
    delay=1
    spinchars='|/-\*'
    for ((i=1; i<=$sleeptime; i++)); do
        temp=${spinchars#?}
        printf " <%c> $i " "$spinchars"
        spinchars=$temp${spinchars%"$temp"}
        sleep $delay
        tempstring="$(printf " [%c] $i " "$spinchars")"
        stringlen=${#tempstring}
        for ((t=1; t<=$stringlen; t++)); do
          printf "\b"
        done # for t ((t=1; t<=${#tempstring}; t++))
    done # for ((i=1; i<=$sleeptime; i++))
    printf "    \b\b\b\b"
}

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
# Some overall output:
echo "${BOLD}Work to be peformed:${NORM}"
echo "${REV}FlexSwitch${NORM} containers: $docker"
echo "${REV}Host${NORM} containers: $hosts"
echo "${REV}Record${NORM} is being kept in ${BOLD}$container_record${NORM}"

function docker_start_flexswitch {
  if [ ! -z "$1" ]; then
    instance="$1"
  fi # if [ ! -z "$1" ]; then
  if [ $dry_run -eq 1 ]; then
    echo "${REV}DRY-RUN: ${NORM}"
    echo -e "\tStarting a docker container type: ${REV}FlexSwitch${NORM}, instance name: ${BOLD}flexswitch$instance${NORM}"
  else
    echo -e "\tStarting a docker container type: ${REV}FlexSwitch${NORM}, instance name: ${BOLD}flexswitch$instance${NORM}"
  container_id=$(sudo docker run -dt --log-driver=syslog --privileged --cap-add ALL --hostname=flexswitch$instance --name flexswitch$instance -P snapos/flex:latest)
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
    echo -e "${YELLOW}Starting a host container isn't supported yet.${NORM}."
  else
    echo -e "\tStarting a docker container type: ${REV}Host${NORM}, instance name: ${BOLD}host$instance${NORM}"
    echo -e "${YELLOW}Starting a host container isn't supported yet.${NORM}."
    #container_id=$(sudo docker run -dt --log-driver=syslog --hostname=host$instance --name host$instance -P snapos/flex:latest)
    #if [ $? -ne 0 ]; then
    #  echo "${RED}ERROR${NORM}Failed starting docker instance \"$instance\". Please check output above and fix" 1>&2
    #  exit 1
    #else
    #  echo -n "$container_id," >> $container_record
    #fi # if [ $? -ne 0 ]
  fi # if [ $dry_run -eq 1 ]
  return 0
}

for ((i=1; i<=$docker; i++));do
  echo "Docker-based FlexSwitch number: $i"
  docker_start_flexswitch $i
  if [ $dry_run -eq 1 ]; then
    echo "${REV}DRY-RUN: ${NORM}"
  else
    namespace=$(sudo docker inspect -f '{{.State.Pid}}' flexswitch$i)
    mgmt_ip=$(sudo docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' flexswitch$i)
    echo "flexswitch$i,$namespace,$mgmt_ip" >> $container_record
    echo -en "\t"; sudo ln -vs /proc/$namespace/ns/net /var/run/netns/$namespace
  fi # if [ $dry_run -eq 1 ]
done # for ((i=1; i<=$docker; i++))

if [ $hosts -ne 0 ]; then
  for ((i=1; i<=$hosts; i++));do
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

echo "Creating $links eth links between flexswitch containers:"

for ((i=1; i<=$links; i++));do
  echo -e "\tLink: $i"
  if [ $dry_run -eq 1 ]; then
    echo -e "\t\t${REV}DRY_RUN:${NORM} make_veth flexswitch1 flexswitch2"
  else
    flexswitch1=$(head -1 $container_record | awk -F "," '{print $3}')
    flexswitch2=$(tail -1 $container_record | awk -F "," '{print $3}')
    make_veth $flexswitch1 $flexswitch2
  fi #  if [ $dry_run -eq 1 ]
done

#
#
#
echo -e "\n\n\n"
echo "**********************************************************************"
echo "Sleeping 60s to allow for the initial Docker container init to finish"
fancy_sleep 60
echo "**********************************************************************"
echo -e "\n\n\n"

echo -e "Start flexswtich to pick up the interfaces "
if [ $dry_run -eq 1 ]; then
  echo "${REV}DRY-RUN${NORM} FlexSwitch restart"
else
  for instance in $(cat $container_record | awk -F "," '{print $2}'); do
    echo -e "\t$instance (logs redirect to $instance.log):"
    sudo docker exec $instance sh -c "/etc/init.d/flexswitch restart" >&2> $instance.log
    if [ $? -ne 0 ]; then
       echo "${RED}ERROR: ${NORM}Starting flexswitch process in docker instance \"$instance\" failed. Please check output above and fix" 1>&2
       exit 1
    fi # if [ $? -ne 0 ]
  done # for instance in $(cat $container_record | awk -F "," '{print $2}')
fi # if [ $dry_run -eq 1 ]

echo -e "\n\n\n"
echo "**********************************************************************"
echo "Sleeping 20s to allow for the FlexSwitch daemons to fully initialize"
fancy_sleep 20
echo "**********************************************************************"
echo -e "\n\n\n"

if [ $dry_run -eq 0 ]; then
  for instance in $(cat $container_record | awk -F "," '{print $2}'); do
    echo "Checking on the status of FlexSwitch in docker instance \"$instance\"..."
    sudo docker exec $instance sh -c "/etc/init.d/flexswitch status"
    if [ $? -ne 0 ]; then
       echo "${RED}ERROR: ${NORM}Checking a flexswitch process in docker instance \"$instance\" failed. Please check output above and fix" 1>&2
       exit 1
    fi # if [ $? -ne 0 ]
  done
fi # if [ $dry_run -eq 0 ]

echo "Network Links:"
if [ $dry_run -eq 1 ]; then
  echo "${REV}DRY-RUN${NORM} netlinks file processing"
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
  echo "${REV}DRY-RUN${NORM} contents of ${BOLD}$container_record${NORM} go here"
else
  cat $container_record
fi # if [ $dry_run -eq 1 ]
