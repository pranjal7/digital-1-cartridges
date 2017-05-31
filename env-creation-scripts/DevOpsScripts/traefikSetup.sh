#!/bin/bash

set -e
##############################
# Constants
##############################
#script_set=()
#temp_script="/tmp/temp_script.sh"
#s3_bucket_url="s3://deveng-bucket"
#aws_script="https://s3-eu-west-1.amazonaws.com/deveng-public/awscli_setup.sh"
masterIp="MASTER_IP_TOKEN"
overlayCidr="192.168.0.0/24"
overlayName="proxy-overlay"
export myIP=$(hostname --ip-address)
user="centos"
userHome="/home/${user}"
auth_file_repo="${userHome}/docker_auth_custom_registry"
auth_file="${auth_file_repo}/config.json"
certPath="${userHome}/.certs"
caCert="${certPath}/ca.pem"
cert="${certPath}/cert.pem"
tlsKey="${certPath}/key.pem"
managerDNS="manager.adop.internal"
traefikDNS="traefik.adop.internal"
consulDNS="consul.adop.internal"
##############################
# Process Args
##############################

#SCRIPTS_EXTRA_ARGS=""

usage() {
  echo "

    Script used to set up traefik using swarm.
    usage: $0 options [-h] -r <ROLE>

    OPTIONS:
       -h,    Show this message.
       -r,    Role determines the type of the application that is going to be installed. i.e. traefik. (mandatory)

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


traefik(){

    log "INFO" "Traefik installation starts..."

	#Set up traefik.toml config file with the following contents (and place in /<path>/<to>/traefik.toml:
	mkdir -p /data/traefik
	sudo tee /data/traefik/traefik.toml <<-'EOF'
	################################################################
	# Web configuration backend
	################################################################
	logLevel = "DEBUG"
	[web]
	address = ":8081"
	################################################################
	# Docker configuration backend
	################################################################
	[docker]
	domain = "adop.internal"
	watch = true
	endpoint = 'tcp://<masterIp>:3376'
	#endpoint = "unix:///var/run/docker.sock"
	#
	# Enable docker TLS connection
	#
	[docker.tls]
	ca = "/etc/ssl/ca.pem"
	cert = "/etc/ssl/cert.pem"
	key = "/etc/ssl/key.pem"
	insecureskipverify = true
	EOF

	sed -i 's/<masterIp>/'"${masterIp}"'/' /data/traefik/traefik.toml

	/bin/sleep 10s
	log "INFO" "Traefik container starts..."

  #--security-opt seccomp:${userHome}/traefik/traefik-seccomp.json \
  # NOTE: add seccomp profiles.
	docker --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run -d \
	-e constraint:environment==${role} --name=${role} \
	--restart=always \
	-v ${certPath}/:/etc/ssl/ \
	-v /data/traefik/traefik.toml:/etc/traefik/traefik.toml \
	-p 80:80 \
	--net=${overlayName} \
	--label traefik.port=8081 \
	traefik

    log "INFO" "Traefik installation finished..."

}


if [ $# == 0 ]; then
    usage
fi


while getopts "t:r:h" opt; do
  case $opt in
    r)
      role=${OPTARG}
      case ${role} in
        "traefik")
          ;;
        *)
          echo "Invalid option: ${role}"
          usage
          ;;
      esac
      ;;
    h)
      echo "Tip: Please provide an argument like master/node..."
      usage
      ;;
    t)
      ;;
    *)
      echo "Invalid parameter(s) or option(s)."
      usage
      ;;
  esac
done


#echo "function traefik is going to run...."
#exit 0

traefik


echo "Traefik app script ends...."
