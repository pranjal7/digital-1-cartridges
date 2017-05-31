#!/bin/bash

set -e
##############################
# Constants
##############################

gluster_brick_mountpoint="/data/GlusterFS/bricks"
gluster_volume_name="vol01"
gluster_host_volume_starter_ip="GLUSTER_HOST_TOKEN"
gluster_server2_ip="GLUSTER_HOST2_TOKEN"
gluster_client_mountpoint="/data/GlusterFS"

wait_max=1800
wait_timer=0

##############################
# Process Args
##############################

usage() {
  echo "

    Script, which given option \"-t server\" will setup GlusterFS servers on ${gluster_host_volume_starter_ip} and ${gluster_server2_ip}. Script will create and start ${gluster_volume_name} from host ${gluster_host_volume_starter_ip}. If option \"-t client\" is given, then the script will setup GlusterFS client and mount ${gluster_volume_name} in ${gluster_client_mountpoint}.

    usage: $0 options [-t <server|client>]

    OPTIONS:
		-h,		Show this message.
		-t,		Select between \"server\" and \"client\" installation.
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

while getopts "t:h" opt; do
	case $opt in
		t)
			setupOption=${OPTARG}
			[[ (${setupOption} == "server") || (${setupOption} == "client") ]] || usage
			;;
		h)
			echo "Requested more info"
			usage
			;;
		*)
			echo "Invalid parameter(s) or option(s)."
			usage
			;;
	esac
done
shift $((OPTIND-1))

if [ -z "${setupOption}" ]; then
    usage
fi

echo "Setup option set as ${setupOption}"

install_packages() {
  export IFS=" "
  for package in $1
    do
      yum install -y ${package}
  done
}

##############################
# Main
##############################
glusterServer() {

  # Setup GlusterFS Server.
	log "INFO" "Starting GlusterFS Server Setup"

  install_packages "xfsprogs centos-release-gluster glusterfs-server glusterfs-cli"

  EBS_STATUS=$(file -s /dev/xvdf | grep "/dev/xvdf: data" > /dev/null ; echo $?)

  if [ "${EBS_STATUS}" = "0" ]; then
    # Format the partition's filesystem if not already formatted.
    mkfs.xfs /dev/xvdf
  fi

	# Make the brick directory and mount the partition as a Gluster "brick"
	# Create mountpoint
	mkdir -p ${gluster_brick_mountpoint}

	# Add an entry to /etc/fstab (mount this volume on every reboot)
  # Should check to see if entry already in fstab
	echo "/dev/xvdf ${gluster_brick_mountpoint} xfs defaults 0 1" >> /etc/fstab

	# Mount all file systems in /etc/fstab
	mount -a

	# Create a directory for the new volume
	mkdir -p ${gluster_brick_mountpoint}/${gluster_volume_name}

	# Add secure-access file to enable Management Encryption for Volumes
	touch /var/lib/glusterd/secure-access

	# Start gluster server
	set +e
	service glusterd start
	if [ $? -ne 0 ]; then
		log "ERROR" "Failed to start glusterd"
	else
		log "INFO" "Succesfully started glusterd"
	fi
	set -e

	# Start this service on boot
	chkconfig glusterd on

	# Add filesystem to kernel
	modprobe fuse

	hostip=$(hostname --ip-address)
	set +e
	if [[ ${hostip} == "${gluster_host_volume_starter_ip}" ]]; then
		log "INFO" "I'm ${gluster_host_volume_starter_ip}, so I'll configure the trusted pool and start the volume."

		# Configure the trusted pool.
		failed_client=false
		gluster peer probe ${gluster_server2_ip}
		while [ $? -ne 0 ]; do
			echo "Client ${gluster_server2_ip} not ready, trying again in 10 seconds..."
			wait_timer=$(($wait_timer + 10))
			sleep 10

			if [ $wait_timer -ge ${wait_max} ]; then
				log "ERROR" "I've waited too long to peer probe: ${gluster_server2_ip}.  Moving on..."
				failed_client=true
				break
			fi

		gluster peer probe ${gluster_server2_ip}
		done

		if [ ${failed_client} != true ]; then
			log "INFO" "Successully added client ${gluster_server2_ip}."
		fi

		# Starting the volume.
		wait_timer=0
		sleep 5
		failed_volume=false
		gluster volume create ${gluster_volume_name} replica 2 ${gluster_host_volume_starter_ip}:${gluster_brick_mountpoint}/${gluster_volume_name}  ${gluster_server2_ip}:${gluster_brick_mountpoint}/${gluster_volume_name}
		while [ $? -ne 0 ]; do
			echo "Could not create gluster volume, trying again in 10 seconds..."
			wait_timer=$(($wait_timer + 10))
			sleep 10

			if [ $wait_timer -ge ${wait_max} ]; then
				log "ERROR" "I've waited too long to create the volume.  Moving on..."
				failed_volume=true
				break
			fi

			sleep 5
			gluster volume create ${gluster_volume_name} replica 2 ${gluster_host_volume_starter_ip}:${gluster_brick_mountpoint}/${gluster_volume_name}  ${gluster_server2_ip}:${gluster_brick_mountpoint}/${gluster_volume_name}
		done

		if [ ${failed_volume} != true ]; then
			log "INFO" "Successully created volume ${gluster_volume_name}."
		fi


		# Enable TLS Identities for Authorization
		gluster volume set ${gluster_volume_name} auth.ssl-allow '*'

		# Enabling TLS on the I/O Path
		gluster volume set ${gluster_volume_name} client.ssl on
		gluster volume set ${gluster_volume_name} server.ssl on

		gluster volume start ${gluster_volume_name}
		if [ $? -ne 0 ]; then
			log "ERROR" "Failed to start ${gluster_volume_name}"
		else
			log "INFO" "Succesfully started ${gluster_volume_name}"
		fi

	fi
	set -e

    log "INFO" "Succesfully finished with GlusterFS Server Setup..."
}

glusterClient() {
	# Setup GlusterFS Client
	log "INFO" "Starting GlusterFS Client Setup"

	# Install the GlusterFS Client:
	install_packages "glusterfs-client"

	# Create a mount point to which you will mount your new volume (vol01)
	mkdir -p ${gluster_client_mountpoint}

	# Add secure-access file to enable Management Encryption for Volumes
	mkdir /var/lib/glusterd/
	touch /var/lib/glusterd/secure-access

	# Mount the GlusterFS volume
	wait_timer=0
	sleep 5
	failed_volume=false
	mount -t glusterfs ${gluster_host_volume_starter_ip}:${gluster_volume_name} ${gluster_client_mountpoint}
		while [ $? -ne 0 ]; do
			echo "Could not mount gluster volume, trying again in 10 seconds..."
			wait_timer=$(($wait_timer + 10))
			sleep 10

			if [ $wait_timer -ge ${wait_max} ]; then
				log "ERROR" "I've waited too long to mount the volume.  Moving on..."
				failed_volume=true
				break
			fi

			sleep 5
			mount -t glusterfs ${gluster_host_volume_starter_ip}:${gluster_volume_name} ${gluster_client_mountpoint}
		done

	if [ ${failed_volume} != true ]; then
		log "INFO" "Succesfully mounted ${gluster_volume_name} in ${gluster_client_mountpoint}."
	fi

}

if [[ ${setupOption} == "server" ]]; then
	glusterServer
elif
 [[ ${setupOption} == "client" ]]; then
	glusterClient
fi
