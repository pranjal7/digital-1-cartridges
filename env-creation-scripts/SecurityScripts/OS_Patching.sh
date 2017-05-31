#!/bin/bash

set -e
##############################
# Constants
##############################


##############################
# Process Args
##############################

log() {
    level=${1}
    message=${2}
    if [ -z "${level}" ]; then echo "Level is empty"; exit 1; fi
    if [ -z "${message}" ]; then echo "Message is empty"; exit 1; fi

    timestamp=$(date '+%Y/%m/%d %H:%M:%S')
    echo "${timestamp}:${level} > ${message}"
}


##############################
# Main
##############################
patchingOS() {

log "INFO" "OS Patching script initiated"

os_dist=$(cat /etc/*-release | grep "ID_LIKE=")
os_dist=${os_dist#*=}

set +e
if [[ ${os_dist} == "debian" ]]; then
	apt-get update
	# apt-get dist-upgrade
	apt-get upgrade -y
	if [ $? -ne 0 ]; then
		log "ERROR" "Patching failed using apt-get tool"
	else
		log "INFO" "OS Patching succeded using apt-get tool"
	fi
elif [[ (${os_dist} =~ "rhel") || (${os_dist} =~ "fedora") ]]; then
	yum check-update
	yum update all -y
	sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/epel.repo
	if [ $? -ne 0 ]; then
		log "ERROR" "Patching failed using yum tool"
	else
		log "INFO" "OS Patching succeded using yum tool"
	fi
else
	log "ERROR" "OS Patching Failed"
fi
 
}
patchingOS
