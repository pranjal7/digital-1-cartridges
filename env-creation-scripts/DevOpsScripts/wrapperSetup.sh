#!/bin/bash

set -e
##############################
# Constants
##############################
start=$(date +%s)
#temp_script="/tmp/temp_script.sh"
#s3_bucket_url="s3://deveng-bucket"
#aws_script="https://s3-eu-west-1.amazonaws.com/deveng-public/awscli_setup.sh"
#masterIP="10.0.5.50"
#consulIP="${masterIP}"
#overlayCidr="192.168.0.0/24"
#overlayName="proxy-overlay"
#export myIP=$(hostname --ip-address)
user="centos"
userHome="/home/${user}"

#statements

#auth_file_repo="${userHome}/docker_auth_custom_registry"
#auth_file="${auth_file_repo}/config.json"
swarm_repo="${userHome}/swarm"
mule_repo="${userHome}/mule"
honeybee_repo="${userHome}/honeybee"
traefik_repo="${userHome}/traefik"
#managerDNS="manager.adop.internal"


usage() {
  echo "

    Script used to call setup scripts for mule or honeybee app using docker swarm depending on the arguments that will be used.
    usage: $0 options [-h] -r <ROLE> [-t] <TYPE>

    OPTIONS:
       -h,    Show this message.
       -t,    Specifies if master or node will be created in swarm. Use \"master\" in case of swarm manager, \"masterReplica\" in case of creating swarm manager replica or \"node\". (mandatory)
       -r,    Application(s) to be installed in the VM. Use mule/honeybee. (optional)

  "
}

log() {
    level=${1}
    message=${2}
    if [ -z "${level}" ]; then echo "Level is empty"; exit 1; fi
    if [ -z "${message}" ]; then echo "Message is empty"; exit 1; fi

    timestamp=$(date '+%Y/%m/%d %H:%M:%S')
    echo "${timestamp}:${level} > ${message}"
}


if [ $# == 0 ] || [[ ! $@ =~ ^\-.+ ]]; then
    usage
    exit 0
fi

while getopts "r:t:h" opt; do
  case $opt in
    r)
      roles=(${OPTARG})
      ;;
    t)
      vmType=${OPTARG}
      case ${vmType} in
        "master"|"node"|"masterReplica")
                                        ;;
        *)
          echo "Invalid option: ${vmType}"
          usage
          exit 1
          ;;
      esac
      ;;
    h)
      echo "Tip: Please provide arguments for master/node/masterReplica and in case of node the application you want to install: mule/honeybee..."
      usage
      exit 0
      ;;
    *)
      echo "Invalid parameter(s) or option(s)."
      usage
      exit 1
      ;;
  esac
done



#if [ -z "${appType}" ] || [ ${#roles[@]} -eq 0 ]; then
#    echo "Parameter value(s) missing"
#    usage
#fi

#IFS=' ' read -ra ROLES_ARRAY <<< "${roles[@]}"
IFS=' '

if [ ${#roles[@]} -ne 0 ]; then
    /bin/bash ${swarm_repo}/swarmSetup.sh -r "${roles[*]}"
else
    script_set+=("${swarm_repo}/swarmSetup.sh")
fi


for role in "${roles[@]}"; do
  case $role in
      honeybee)
              script_set+=("${honeybee_repo}/honeybeeSetup.sh -r ${role}")
              ;;
      mule)
           script_set+=("${mule_repo}/muleSetup.sh -r ${role}")
           ;;
      traefik)
              script_set+=("${traefik_repo}/traefikSetup.sh -r ${role}")
              ;;
    *)
      echo "Invalid option: ${role}"
      usage
      exit 1
      ;;

  esac
done

if ([ "${vmType}" == "master" ] || [ "${vmType}" == "masterReplica" ]) && [ ${#roles[@]} -ne 0 ]; then
    echo "Are you sure you want to install the application(s) in master VM?"
    echo "Please enter yes or [ENTER] for exit"
    read answer
    if [[ "${answer}" != "yes" ]]; then
        usage
        exit 0
    fi
fi


#echo "before app install"
#exit 0

#echo "this is ech: " ${script_set[0]} -t ${vmType}
#/bin/bash ${script_set[0]} -t ${vmType}

for script in "${script_set[@]}"; do
#  aws s3 cp "${s3_bucket_url}/${script}" ${temp_script}
  /bin/bash ${script} -t ${vmType}
#  rm -f ${temp_script}
done


end=$(date +%s)
duration=$((end-start))
echo "Wrapper script duration: ${duration}"
