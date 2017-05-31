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

logRotation() {

cat <<EOT >> /etc/logrotate.d/docker-containers
/var/lib/docker/containers/*/*.log 
{
	rotate 7
	daily
	compress
	size=1M
	missingok
	delaycompress
	dateext
	copytruncate	
}
EOT
}
logRotation