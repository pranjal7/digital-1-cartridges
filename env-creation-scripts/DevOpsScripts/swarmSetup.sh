#!/bin/bash

set -e
##############################
# Constants
##############################
#script_set=()
#temp_script="/tmp/temp_script.sh"
#s3_bucket_url="s3://deveng-bucket"
#aws_script="https://s3-eu-west-1.amazonaws.com/deveng-public/awscli_setup.sh"
masterIP="MASTER_IP_TOKEN"
masterReplicaIP="0.0.0.0"
consulIP=${masterIP}
overlayCidr="192.168.0.0/24"
overlayName="proxy-overlay"
export myIP=$(hostname --ip-address)
user="centos"
userHome="/home/${user}"
auth_file_repo="${userHome}/docker_auth_custom_registry"
auth_file="${auth_file_repo}/config.json"
userHomeSedPath="\/home\/${user}"
certPath="/home/${user}/.certs"
certSedPath="${userHomeSedPath}\/.certs"
caCert="${certSedPath}\/ca.pem"
cert="${certSedPath}\/cert.pem"
tlsKey="${certSedPath}\/key.pem"
consulDNS="consul.adop.internal"
#internalNet="adop.internal"
containerMasterCerts="/certs"
managerDNS="manager.adop.internal"
managerReplicaDNS="manager_replica.adop.internal"
muleDNS="mule.adop.internal"
honeybeeDNS="honeybee.adop.internal"
traefikDNS="traefik.adop.internal"
##############################
# Process Args
##############################

#SCRIPTS_EXTRA_ARGS=""

usage() {
  echo "

    Script used to setup mule & honeybee using swarm.
    usage: $0 options [-h] -r <ROLE> [-a] <APPLICATION>

    OPTIONS:
       -h,    Show this message.
       -r,    Role determines if the master or node will be created in swarm. Use \"master\" in case of swarm manager, \"masterReplica\" in case of another swarm manager or \"node\". (mandatory)
       -a,    Application to be installed in the VM. Use mule/honeybee. (optional)

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

swarmMaster(){

      log "INFO" "Set up and running swarm for master..."
      service docker restart

      log "INFO" "Running docker container for consul..."
      docker run -d -p 8400:8400 -p 8500:8500 -p 8600:53/udp -h "consul" --name=consul --restart="always" progrium/consul -server -bootstrap
      #sed -i -r 's/(OPTIONS\=\"\-\-default-ulimit nofile=1024:4096)\"/\1 -H unix:\/\/\/var\/run\/docker.sock \-H tcp:\/\/0.0.0.0:2375 \-\-cluster\-store\=consul:\/\/'${consulIP}':8500 \-\-cluster\-advertise\='${masterIP}':2375"/' /etc/sysconfig/docker
      sed -i -r 's|(ExecStart=/usr/bin/dockerd).*|\1 --default-ulimit nofile=1024:4096  -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2376 --tlsverify --tlscacert='${caCert}' --tlscert='${cert}' --tlskey='${tlsKey}' --cluster-store=consul://'${consulDNS}':8500 --cluster-advertise='${masterIP}':2376|'  /usr/lib/systemd/system/docker.service

      #OPTIONS="--default-ulimit nofile=1024:4096 -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2376 --cluster-store=consul://consul.adop.internal:8500 --cluster-advertise=10.0.5.50:2376"
      systemctl daemon-reload
      service docker restart
      #Set swarm master
      log "INFO" "Set ${myIP} VM as swarm master..."

      docker run -d -p 3376:3376 --name="swarm_manager" --restart="always" -v ${certPath}:${containerMasterCerts}:ro swarm manage --host=0.0.0.0:3376 --replication --tlsverify --tlscacert=${containerMasterCerts}/ca.pem \
      --tlscert=${containerMasterCerts}/cert.pem --tlskey=${containerMasterCerts}/key.pem --advertise ${managerDNS}:3376 consul://${consulDNS}:8500
      #Set-up overlay network
      sleep 20
      log "INFO" "Creating ${overlayName} network..."
      docker network create --driver overlay --subnet=${overlayCidr} ${overlayName}

      log "INFO" "Swarm manager is now added..."
}

swarmNode(){

      log "INFO" "Set up and running swarm for ${myIP} node..."
      #sed -i -r 's/(OPTIONS\=\"\-\-default-ulimit nofile=1024:4096)\"/\1 -H unix:\/\/\/var\/run\/docker.sock \-\-label environment\='${roles[*]}' \-H tcp:\/\/0.0.0.0:2375 \-\-cluster\-store\=consul:\/\/'${consulIP}':8500 \-\-cluster\-advertise\='${myIP}':2375"/' /etc/sysconfig/docker
      sed -i -r 's|(ExecStart=/usr/bin/dockerd).*|\1 --default-ulimit nofile=1024:4096 -H unix:///var/run/docker.sock --label environment='${roles[*]}' -H tcp://0.0.0.0:2376 --tlsverify --tlscacert='${caCert}' --tlscert='${cert}' --tlskey='${tlsKey}' --cluster-store=consul://'${consulDNS}':8500 --cluster-advertise='${myIP}':2376|' /usr/lib/systemd/system/docker.service
      #OPTIONS="--default-ulimit nofile=1024:4096 -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2376 --tlsverify --tlscacert=${tlsCaCert} --tlscert=${tlsCert} --tlskey=${tlsKey} --cluster-store=consul://consul.adop.internal:8500 --cluster-advertise=10.0.6.6:2376"
      systemctl daemon-reload
      service docker restart
      #Set swarm nodes
      log "INFO" "Node swarm join"

      echo "roles: ${roles[*]}"
      for role in "${roles[@]}"; do
          case $role in
              honeybee)
                      #docker run -d --restart="always" --name=${role} swarm join --advertise=${myIP}:2375 consul://${consulIP}:8500
                      docker run -d --restart="always" --name=${role} swarm join --advertise="${honeybeeDNS}":2376 consul://${consulDNS}:8500
                      #docker run -d --restart="always" --name=mule swarm join --advertise=mule.adop.internal:2376 consul://consul.adop.internal:8500
                      ;;
              mule)
                  #docker run -d --restart="always" --name=${role} swarm join --advertise=${myIP}:2375 consul://${consulIP}:8500
                  docker run -d --restart="always" --name=${role} swarm join --advertise="${muleDNS}":2376 consul://${consulDNS}:8500
                  ;;
              traefik)
                     #docker run -d --restart="always" --name=${role} swarm join --advertise=${myIP}:2375 consul://${consulIP}:8500
                     docker run -d --restart="always" --name=${role}-swarm-agent swarm join --advertise="${traefikDNS}":2376 consul://${consulDNS}:8500
                     ;;
          esac
      done

      log "INFO" "Swarm node ${myIP} is now added..."
}

swarmMasterReplica(){

      log "INFO" "Set up and running swarm replica for master..."
      #service docker restart

      sed -i -r 's|(ExecStart=/usr/bin/dockerd).*|\1 --default-ulimit nofile=1024:4096 -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2376 --tlsverify --tlscacert='${caCert}' --tlscert='${cert}' --tlskey='${tlsKey}' --cluster-store=consul://'${consulDNS}':8500 --cluster-advertise='${masterReplicaIP}':2376|'  /usr/lib/systemd/system/docker.service
      #OPTIONS="--default-ulimit nofile=1024:4096 -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2376 --cluster-store=consul://consul.adop.internal:8500 --cluster-advertise=10.0.5.50:2376"
      systemctl daemon-reload
      service docker restart
      #Set swarm master
      log "INFO" "Set ${myIP} VM as swarm master replica..."

      docker run -d -p 3376:3376 --name="swarm_manager_replica" --restart="always" -v ${certPath}:${containerMasterCerts}:ro swarm manage --host=0.0.0.0:3376 --replication --tlsverify --tlscacert=${containerMasterCerts}/ca.pem \
      --tlscert=${containerMasterCerts}/cert.pem --tlskey=${containerMasterCerts}/key.pem --advertise ${managerReplicaDNS}:3376 consul://${consulDNS}:8500

      log "INFO" "Docker swarm replica for master has been set..."

}


dockerSwarm() {

      # Install and setups Docker.

      log "INFO" "Installing docker..."
      #aws ec2 create-security-group --group-name "docker" --description "Docker security group" --vpc-id "vpc-f4897190"
      #aws ec2 authorize-security-group-ingress --group-name "docker" --protocol tcp --port 22 --cidr 0.0.0.0/0
      #aws ec2 authorize-security-group-ingress --group-name "docker" --protocol tcp --port 80 --cidr 0.0.0.0/0
      #yum -y update
      curl -sSL https://get.docker.com/ | sh
      usermod -aG docker $user

      if [[ "${vmType}" == "master" ]]; then
          swarmMaster
      elif [[ "${vmType}" == "masterReplica" ]]; then
          swarmMasterReplica
      else
          swarmNode
      fi

        log "INFO" "Adding swarm alias to ~/.bashrc"
        #Add swarm alias
        echo "alias swarm='docker --tlsverify --tlscacert=${certPath}/ca.pem --tlscert=${certPath}/cert.pem --tlskey=${certPath}/key.pem -H ${managerDNS}:3376'" | tee -a /root/.bashrc ${userHome}/.bashrc > /dev/null
      log "INFO" "Finished with docker..."
}


if [ $# == 0 ] || [[ ! $@ =~ ^\-.+ ]]; then
    usage
fi


while getopts "t:r:h" opt; do
  case $opt in
    t)
      vmType=${OPTARG}
      case ${vmType} in
        "master"|"node"|"masterReplica")
          ;;
        *)
          echo "Invalid option: ${vmType}"
          usage
          ;;
      esac
      ;;
    r)
      roles=(${OPTARG})
      ;;
    h)
      echo "Tip: Please provide an argument like master/node..."
      usage
      ;;
    *)
      echo "Invalid parameter(s) or option(s)."
      usage
      ;;
  esac
done


#IFS=' '
#for some in "${roles[@]}"; do
#        echo "this is role: ${some}"
#done

#echo "function docker swarm is going to run...."
#exit 0

dockerSwarm


echo "swarmSetup script ends...."
