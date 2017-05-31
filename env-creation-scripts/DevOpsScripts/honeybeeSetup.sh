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
user="centos"
userHome="/home/${user}"
export myIP=$(hostname --ip-address)
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
       -r,    Role determines the type of the application that is going to be installed. i.e. honeybeeApp. (mandatory)

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


honeybee(){

    log "INFO" "Honeybee installation starts..."

    #HEADER=$(echo "{\"username\":\"devops.training\",\"password\":\"ztNsaJPyrSyrPdtn\"}" | base64 -w 0)
    HEADER="eyJ1c2VybmFtZSI6ImRldm9wcy50cmFpbmluZyIsInBhc3N3b3JkIjoienROc2FKUHlyU3lyUGR0biJ9Cg=="
    mkdir -p ${auth_file_repo}
    echo -e "{\n\t\"HttpHeaders\": { \n\t\t\"X-Registry-Auth\": \"${HEADER}\" \n\t}\n}"  > ${auth_file}

    mkdir -p /data/{tomcat,mongodb,refdata}/
    mkdir -p /data/tomcat/webapps/
    wget https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/conf/hb/hb-mdi-rest-app.war -O /data/tomcat/webapps/ROOT.war
    wget https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/conf/hb/hb-mdi-ui.war -O /data/tomcat/webapps/salesforce.war
    wget https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/scripts/mongo_import.sh -O /data/refdata/mongo_import.sh
    chmod +x /data/refdata/mongo_import.sh
    wget https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/conf/hb/hb-mdi-data.zip -O /data/refdata/hb-mdi-data.zip
    unzip -o /data/refdata/hb-mdi-data.zip -d /data/refdata/hb-mdi-data
    unzip -o /data/tomcat/webapps/ROOT.war -d /data/tomcat/webapps/ROOT
    unzip -o /data/tomcat/webapps/salesforce.war -d /data/tomcat/webapps/salesforce
    sed -i s#mongodb.url[[:space:]]*=.*#mongodb.url=hb-mongodb-env001:27017# /data/tomcat/webapps/ROOT/WEB-INF/classes/application.properties
    sed -i s#application_security.login.url[[:space:]]*=.*#application_security.login.url=http://hb-webapp-env001:8080/hb/index.html# /data/tomcat/webapps/ROOT/WEB-INF/classes/application.properties
    sed -i s#integration.mule.header.endPoint[[:space:]]*=.*#integration.mule.header.endPoint=http://afp4mule-env001/api/# /data/tomcat/webapps/ROOT/WEB-INF/classes/application.properties
    sed -i 's#customer.getcustomer.get.endpoint[[:space:]]*=.*#customer.getcustomer.get.endpoint=http://afp4mule-env001/api/customers?firstName={Jon}\\&surname={Doe}\\&postCode={W1C3BP}#' /data/tomcat/webapps/ROOT/WEB-INF/classes/application.properties
    sed -i s#products.getproducts.get.endpoint[[:space:]]*=.*#products.getproducts.get.endpoint=http://afp4mule-env001/api/products# /data/tomcat/webapps/ROOT/WEB-INF/classes/application.properties
    sed -i s#orders.getorders.get.endpoint[[:space:]]*=.*#orders.getorders.get.endpoint=http://afp4mule-env001/api/orders?customerId=0032400000BJRbK# /data/tomcat/webapps/ROOT/WEB-INF/classes/application.properties
    echo 'var hb = {};' > /data/tomcat/webapps/salesforce/js/properties.js
    echo 'hb.endpoints = {};' >> /data/tomcat/webapps/salesforce/js/properties.js
    echo 'hb.endpoints.api = "http://hb-webapp-env001.adop.internal";' >> /data/tomcat/webapps/salesforce/js/properties.js
    echo 'hb.proposal = { badge: "Proposal" };' >> /data/tomcat/webapps/salesforce/js/properties.js
    echo 'hb.customer = { badge: "Proposal" };' >> /data/tomcat/webapps/salesforce/js/properties.js
    echo 'hb.orders   = { badge: "Order" };' >> /data/tomcat/webapps/salesforce/js/properties.js

	set +e
    log "INFO" "MongoDb for Honeybee container starts..."
    docker  --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run --security-opt seccomp:${userHome}/honeybee/docker.accenture.com-afp4mule-mongodb-seccomp.json -e constraint:environment==${role} --name=hb-mongodb-env001 --restart=always --net=${overlayName} -e SERVICE_27017_NAME=hb-mongodb-env001 -dt -p 27017:27017 -e MONGO_AUTH=false docker.accenture.com/afp4mule/mongodb:0.0.2
	while [ $? -ne 0 ]; do
			echo "Could not create MongoDB container, trying again in 2 seconds..."
			wait_timer=$(($wait_timer + 2))
			sleep 2

			if [ $wait_timer -ge ${wait_max} ]; then
				log "ERROR" "I've waited too long to create the MongoDB container.  Moving on..."
				break
			fi
			docker  --config=${auth_file_repo} --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run --security-opt seccomp:${userHome}/honeybee/docker.accenture.com-afp4mule-mongodb-seccomp.json -e constraint:environment==${role} --name=hb-mongodb-env001 --restart=always --net=${overlayName} -e SERVICE_27017_NAME=hb-mongodb-env001 -dt -p 27017:27017 -e MONGO_AUTH=false docker.accenture.com/afp4mule/mongodb:0.0.2
	done
    #sleep 60 && docker exec hb-mongodb-env001 /data/refdata/mongo_import.sh -c refdata -d hb-mdi -f /data/refdata/hb-mdi-data/refData
    #docker exec hb-mongodb-env001 /data/refdata/mongo_import.sh -c configdata -d hb-mdi -f /data/refdata/hb-mdi-data/ConfigurationData

    log "INFO" "Tomcat server container starts..."
    docker --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run --security-opt seccomp:${userHome}/honeybee/tomcat-seccomp.json -e constraint:environment==${role} --name=hb-webapp-env001 --restart=always --net=${overlayName} -e SERVICE_CHECK_SCRIPT="curl --silent --fail $IP:8080/salesforce/index.html" -e SERVICE_8080_NAME=hb-webapp-env001 -dt -v /data/tomcat/webapps/:/usr/local/tomcat/webapps/ -p 8080:8080 tomcat:8-jre8
	while [ $? -ne 0 ]; do
			echo "Could not create Tomcat container, trying again in 2 seconds..."
			wait_timer=$(($wait_timer + 2))
			sleep 2

			if [ $wait_timer -ge ${wait_max} ]; then
				log "ERROR" "I've waited too long to create the Tomcat container.  Moving on..."
				break
			fi
			docker --tlsverify --tlscacert=${caCert} --tlscert=${cert} --tlskey=${tlsKey} -H ${managerDNS}:3376 run --security-opt seccomp:${userHome}/honeybee/tomcat-seccomp.json -e constraint:environment==${role} --name=hb-webapp-env001 --restart=always --net=${overlayName} -e SERVICE_CHECK_SCRIPT="curl --silent --fail $IP:8080/salesforce/index.html" -e SERVICE_8080_NAME=hb-webapp-env001 -dt -v /data/tomcat/webapps/:/usr/local/tomcat/webapps/ -p 8080:8080 tomcat:8-jre8
	done
    #docker run --name=hb-mongo-browser --restart=always -e SERVICE_8085_NAME=hb-mongo-browser -p 8085:8081 --link hb-mongodb-env001:mongo -td knickers/mongo-express:
    #curl https://s3-eu-west-1.amazonaws.com/adop-framework-afp4mule/scripts/get_deployment_key.sh | bash

    log "INFO" "Honeybee app installation finished..."

}


if [ $# == 0 ]; then
    usage
fi


while getopts "t:r:h" opt; do
  case $opt in
    r)
      role=${OPTARG}
      case ${role} in
        "honeybee")
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


#echo "function honeybee is going to run...."
#exit 0

honeybee


echo "Honeybee app script ends...."
