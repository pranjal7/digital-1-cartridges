#!/bin/bash

set -e
##############################
# Constants
##############################
#script_set=()
#temp_script="/tmp/temp_script.sh"
#s3_bucket_url="s3://deveng-bucket"
#aws_script="https://s3-eu-west-1.amazonaws.com/deveng-public/awscli_setup.sh"
#masterIp="10.0.5.50"
#overlayCidr="192.168.0.0/24"
#overlayName="proxy-overlay"
#export myIP=$(hostname --ip-address)
#auth_file_repo="/home/ec2-user/docker_auth_custom_registry"
#auth_file="${auth_file_repo}/config.json"
#certPath="/home/ec2-user/.certs"
#caCert="${certPath}/ca.pem"
#cert="${certPath}/cert.pem"
#tlsKey="${certPath}/key.pem"
#managerDNS="manager.adop.internal"


usage() {
  echo "

    Script used to install openVAS through docker.
    usage: $0 options [-h] 

    OPTIONS:
       -h,    Show this message.
              The script does not take any arguments and used in order to install openVAS as docker container.
  "
  exit 0
}

log() {
    level=${1}
    message=${2}
    if [ -z "${level}" ]; then echo "Level is empty"; exit 1; fi
    if [ -z "${message}" ]; then echo "Message is empty"; exit 1; fi

    timestamp=$(date '+%Y/%m/%d %H:%M:%S')
    echo "${timestamp}:${level} > ${message}"
}


openVAS(){

    log "INFO" "Installing docker..."
    curl -sSL https://get.docker.com/ | sh
    usermod -aG docker ec2-user

    log "INFO" "Running openVAS docker container in order to install the application."
    docker run -d -p 443:443 -p 9390:9390 -p 9391:9391 --name openvas mikesplain/openvas

}


while getopts "h" opt; do
  case $opt in
    h)
      usage
      ;;
    *)
      echo "Invalid parameter(s) or option(s)."
      usage
      ;;
  esac
done


echo "test finish"
exit 0
openVAS


echo "openVAS installation script ends...."
