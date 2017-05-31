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

wait_max=1800
wait_timer=0
##############################
# Process Args
##############################

#SCRIPTS_EXTRA_ARGS=""

usage() {
  echo "

    Script used to setup mule & honeybee using swarm.
    usage: $0 options [-h] -r <ROLE>

    OPTIONS:
       -h,    Show this message.
       -r,    Role determines the type of the application that is going to be installed. i.e. muleApp. (mandatory)

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


mule(){

    log "INFO" "Mule installation starts..."

    mkdir -p /data/{mule,mongodb,rabbitmq}
    mkdir -p /data/mule/{apps,conf}

    yum install -y wget
    yum install -y unzip

    wget https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/conf/mule_ee/muleLicenseKey.lic -O /data/mule/conf/muleLicenseKey.lic
    wget https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/conf/mule_ee/sf-api.zip -O /data/mule/apps/sf-api.zip
    unzip -o /data/mule/apps/sf-api.zip -d /data/mule/apps/sf-api

    HEADER=$(echo "{\"username\":\"devops.training\",\"password\":\"ztNsaJPyrSyrPdtn\"}" | base64 -w 0)
    mkdir -p ${auth_file_repo}
    echo -e "{\n\t\"HttpHeaders\": { \n\t\t\"X-Registry-Auth\": \"${HEADER}\" \n\t}\n}"  > ${auth_file}

	set +e
    log "INFO" "MongoDb container starts..."
    #mongoDb container
	docker  --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run  -e constraint:environment==${role} --name=mongodb --restart=always --net=${overlayName} -e SERVICE_27017_NAME=afp4mule-mongodb-env001 -v /data/mongodb:/data/db -dt -p 27017:27017 -e MONGO_DB=mydb -e MONGO_USER=afp4mule -e MONGO_PASSWORD=afp4mule docker.accenture.com/afp4mule/mongodb:0.0.2
    while [ $? -ne 0 ]; do
			echo "Could not create MongoDB container, trying again in 2 seconds..."
			wait_timer=$(($wait_timer + 2))
			sleep 2

			if [ $wait_timer -ge ${wait_max} ]; then
				log "ERROR" "I've waited too long to create the MongoDB container.  Moving on..."
				break
			fi
			docker  --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run -e constraint:environment==${role} --name=mongodb --restart=always --net=${overlayName} -e SERVICE_27017_NAME=afp4mule-mongodb-env001 -v /data/mongodb:/data/db -dt -p 27017:27017 -e MONGO_DB=mydb -e MONGO_USER=afp4mule -e MONGO_PASSWORD=afp4mule docker.accenture.com/afp4mule/mongodb:0.0.2
	done

    log "INFO" "Rabbitmq container starts..."
    #rabbitmq container
    docker  --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run  -e constraint:environment==${role} --net=${overlayName} --name=rabbitmq --restart=always -e SERVICE_5672_NAME=afp4mule-rabbitmq-env001 -v /data/rabbitmq:/var/lib/rabbitmq -td -p 8080:8080 -p 5672:5672 -p 15672:15672 -e RABBITMQ_DEFAULT_USER=rabbitmq -e RABBITMQ_DEFAULT_PASS=rabbitmq123 -e RABBITMQ_EXCHANGES="Exception:fanout MessageHub:fanout" --label traefik.port=15672 docker.accenture.com/afp4mule/rabbitmq:0.0.2
	while [ $? -ne 0 ]; do
			echo "Could not create RabbitMQ container, trying again in 2 seconds..."
			wait_timer=$(($wait_timer + 2))
			sleep 2

			if [ $wait_timer -ge ${wait_max} ]; then
				log "ERROR" "I've waited too long to create the RabbitMQ container.  Moving on..."
				break
			fi
			docker  --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run  -e constraint:environment==${role} --net=${overlayName} --name=rabbitmq --restart=always -e SERVICE_5672_NAME=afp4mule-rabbitmq-env001 -v /data/rabbitmq:/var/lib/rabbitmq -td -p 8080:8080 -p 5672:5672 -p 15672:15672 -e RABBITMQ_DEFAULT_USER=rabbitmq -e RABBITMQ_DEFAULT_PASS=rabbitmq123 -e RABBITMQ_EXCHANGES="Exception:fanout MessageHub:fanout" --label traefik.port=5672 docker.accenture.com/afp4mule/rabbitmq:0.0.2
	done

    log "INFO" "Mule container starts..."
    #mule container
    docker  --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run  --name=mule-runtime -e constraint:environment==${role} --net=${overlayName} --restart=always -e SERVICE_8084_NAME=afp4mule-mule-env001 -v /data/mule/conf/:/opt/mule/conf/ -v /data/mule/apps/:/opt/mule/apps/ -v /data/mule/logs:/opt/mule/logs -p 5000:5000 -p 1098:1098 -p 7777:7777 -p 8081:8081 -p 8084:8084 -td --label traefik.port=8081 docker.accenture.com/afp4mule/mule_ee:2.0.0
	while [ $? -ne 0 ]; do
			echo "Could not create Mule_ee container, trying again in 2 seconds..."
			wait_timer=$(($wait_timer + 2))
			sleep 2

			if [ $wait_timer -ge ${wait_max} ]; then
				log "ERROR" "I've waited too long to create the Mule_ee container.  Moving on..."
				break
			fi
			docker  --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run  --name=mule-runtime -e constraint:environment==${role} --net=${overlayName} --restart=always -e SERVICE_8084_NAME=afp4mule-mule-env001 -v /data/mule/conf/:/opt/mule/conf/ -v /data/mule/apps/:/opt/mule/apps/ -v /data/mule/logs:/opt/mule/logs -p 5000:5000 -p 1098:1098 -p 7777:7777 -p 8081:8081 -p 8084:8084 -td --label traefik.port=8081 docker.accenture.com/afp4mule/mule_ee:2.0.0
	done

  mkdir -p /data/tomcat/webapps/
  wget https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/conf/muleframework/AFP4Mule.war -O /data/tomcat/webapps/ROOT.war

  log "INFO" "Mule framework container starts..."
  #mule container
  docker --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run -td --restart=always --net=${overlayName} -e SERVICE_CHECK_SCRIPT="curl --silent --fail $IP:80/journeys/muleFramework" -e SERVICE_8080_NAME=afp4mule-framework --name afpmule-framework -e constraint:environment==${role} -v /data/tomcat/webapps/:/usr/local/tomcat/webapps/ -e NEXUS_USER=admin -e NEXUS_PASSWORD=afp4mule -e NEXUS_URL=52.49.233.196/nexus --label traefik.port=8080 dockerhub.accenture.com/digital-1/mule_framework:0.0.3
  while [ $? -ne 0 ]; do
      echo "Could not create mule_framework container, trying again in 2 seconds..."
      wait_timer=$(($wait_timer + 2))
      sleep 2

      if [ $wait_timer -ge ${wait_max} ]; then
        log "ERROR" "I've waited too long to create the mule_framework container.  Moving on..."
        break
      fi
      docker --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run -td --restart=always --net=${overlayName} -e SERVICE_CHECK_SCRIPT="curl --silent --fail $IP:80/journeys/muleFramework" -e SERVICE_8080_NAME=afp4mule-framework --name afpmule-framework -e constraint:environment==${role} -v /data/tomcat/webapps/:/usr/local/tomcat/webapps/ -e NEXUS_USER=admin -e NEXUS_PASSWORD=afp4mule -e NEXUS_URL=52.49.233.196/nexus --label traefik.port=8080 dockerhub.accenture.com/digital-1/mule_framework:0.0.3
  done


    #curl https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/scripts/get_deployment_key.sh | bash

    log "INFO" "MongoDb, RabbitMq, Mule, mule framework installations finished..."
}


if [ $# == 0 ]; then
    usage
fi


while getopts "t:r:h" opt; do
  case $opt in
    r)
      role=${OPTARG}
      case ${role} in
        "mule")
          ;;
        *)
          echo "Invalid option: ${role}"
          usage
          ;;
      esac
      ;;
    h)
      echo "Tip: Please provide an argument like muleApp..."
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


#echo "function mule is going to run...."
#exit 0

mule


echo "Mule app script ends...."
