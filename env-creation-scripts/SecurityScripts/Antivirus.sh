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

antivirusInst() {

log "INFO" "Antivirus setup script initiated"

os_dist=$(cat /etc/*-release | grep "ID_LIKE=")
os_dist=${os_dist#*=}

set +e
if [[ ${os_dist} == "debian" ]]; then

	apt-get install -y clamav clamav-daemon
	
	# Obtain the latest ClamAV anti-virus signature databases (happens by default afterwars)
	freshclam
	
	# Add clamav service to Ubuntu with the update-rc.d command, accepting the default run levels.
	update-rc.d clamav-daemon defaults
	update-rc.d clamav-freshclam defaults
	
	# Start the clamav-daemon service
	service clamav-daemon start
	
	# Install sendmail
	apt-get install -y sendmail
	
	mkdir /var/log/clamav/clamscan
	
	# Add a script to perform daily ClamAV scans
		cat <<"EOT" >> /etc/clamav/clamscan.sh
#!/bin/bash
 
# Directories to scan
SCAN_DIR="/home"
 
# Location of log file
SCAN_TIME=$(date +%Y_%m_%d_%R)
LOG_FILE=/var/log/clamav/clamscan/LastScan.$SCAN_TIME
  
# Email To
EMAIL="nikolaos.karapanos@accenture.com"

# Email From
EMAIL_FROM="AWS_VM"

# Email Subject
HOST_N=$(hostname -i)
SUBJECT="Infections detected on $HOST_N host after running ClamAV scan at $SCAN_TIME"

clamscan -ri $SCAN_DIR > $LOG_FILE

email_scan () {
    if [ `tail -n 12 ${LOG_FILE}  | grep Infected | grep -v 0 | wc -l` != 0 ]
    then
    # Counting the total number of infections
        SCAN_RESULTS=$(tail -n 10 $LOG_FILE | grep 'Infected files')
        INFECTIONS=${SCAN_RESULTS##* }
		
		EMAIL_TIME=$(date +%Y_%m_%d_%R)
		touch "/var/log/clamav/clamscan/clamEmail.$EMAIL_TIME"
        EMAILMESSAGE="/var/log/clamav/clamscan/clamEmail.$EMAIL_TIME"
        echo "To: ${EMAIL}" >>  ${EMAILMESSAGE}
        echo "From: ${EMAIL_FROM}" >>  ${EMAILMESSAGE}
        echo "Subject: ${SUBJECT}" >>  ${EMAILMESSAGE}
		echo -e "\n`tail -n $((10 + $INFECTIONS)) $LOG_FILE`" >> ${EMAILMESSAGE}
 
        sendmail -t < ${EMAILMESSAGE}
    fi
}

email_scan
EOT
	
	chmod +x /etc/clamav/clamscan.sh
	
	# add Cron to run clamscan daily a scheduled job
	sudo cat <<EOT >> /var/spool/cron/crontabs/root
# Run ClamAV scan Daily
@daily /etc/clamav/clamscan.sh -quiet
EOT


	# Run updates for ClamAV database daily
	sudo cat <<EOT >> /var/spool/cron/crontabs/root
# Run ClamAV Database Updates daily
30 23 * * * /usr/bin/freshclam -quiet
EOT
	
	#clamconf
	
	# Run a test scan
	clamscan -r /tmp	
	if [ $? -ne 0 ]; then
		log "ERROR" "ClamAV installation failed using apt-get tool"
	else
		log "INFO" "ClamAV installation succeeded using apt-get tool"
	fi
	
elif [[ (${os_dist} =~ "rhel") || (${os_dist} =~ "fedora") ]]; then
	
	yum install -y clamav clamd clamav-update
	
	# Remove “Example” line from freshclam.conf and /etc/clamd.d/scan.conf
	sed -i -e 's/^Example/#Example/' /etc/freshclam.conf
	sed -i -e 's/^Example/#Example/' /etc/clamd.d/scan.conf	
	
	# remove last line from /etc/sysconfig/freshclam to enable freshclam automatic updates
	sed -i '$d' /etc/sysconfig/freshclam
	
	# Obtain the latest ClamAV anti-virus signature databases (happens by default afterwars)
	freshclam
		
	# edit the ClamAV daemon file in /etc/clamd.d/scan.conf
	sed -i -e '0,/#LogFile/ s/#LogFile/LogFile/' /etc/clamd.d/scan.conf
	sed -i -e 's/^User clamscan/#User clamscan/' /etc/clamd.d/scan.conf
	sed -i -e 's/^AllowSupplementaryGroups yes/#AllowSupplementaryGroups yes/' /etc/clamd.d/scan.conf
	sed -i -e '0,/#LocalSocket/ s/^#LocalSocket/LocalSocket/' /etc/clamd.d/scan.conf
	
	# edit the clamav config in /etc/clamd.conf (copy form scan.conf)
	cp /etc/clamd.d/scan.conf /etc/clamd.conf
		 
	# Add a script to perform daily ClamAV scans
	cat <<"EOT" >> /etc/clamd.d/clamscan.sh
#!/bin/bash
 
# Directories to scan
SCAN_DIR="/home"
 
# Location of log file
SCAN_TIME=$(date +%Y_%m_%d_%R)
LOG_FILE=/var/log/clamscan/LastScan.$SCAN_TIME
  
# Email To
EMAIL="nikolaos.karapanos@accenture.com"

# Email From
EMAIL_FROM="AWS_VM"

# Email Subject
HOST_N=$(hostname -i)
SUBJECT="Infections detected on $HOST_N host after running ClamAV scan at $SCAN_TIME"

clamscan -ri $SCAN_DIR > $LOG_FILE

email_scan () {
    if [ `tail -n 12 ${LOG_FILE}  | grep Infected | grep -v 0 | wc -l` != 0 ]
    then
    # Counting the total number of infections
        SCAN_RESULTS=$(tail -n 10 $LOG_FILE | grep 'Infected files')
        INFECTIONS=${SCAN_RESULTS##* }
		
		EMAIL_TIME=$(date +%Y_%m_%d_%R)
		touch "/var/log/clamscan/clamEmail.$EMAIL_TIME"
        EMAILMESSAGE="/var/log/clamscan/clamEmail.$EMAIL_TIME"
        echo "To: ${EMAIL}" >>  ${EMAILMESSAGE}
        echo "From: ${EMAIL_FROM}" >>  ${EMAILMESSAGE}
        echo "Subject: ${SUBJECT}" >>  ${EMAILMESSAGE}
		echo -e "\n`tail -n $((10 + $INFECTIONS)) $LOG_FILE`" >> ${EMAILMESSAGE}
 
        sendmail -t < ${EMAILMESSAGE}
    fi
}

email_scan
EOT
	
	chmod +x /etc/clamd.d/clamscan.sh
	mkdir /var/log/clamscan
	
	# add Cron to run clamscan daily a scheduled job
	sudo cat <<EOT >> /var/spool/cron/root
# Run ClamAV scan Daily
@daily /etc/clamd.d/clamscan.sh -quiet
EOT

	# Run updates for ClamAV database daily
	sudo cat <<EOT >> /var/spool/cron/root
# Run ClamAV Database Updates daily
30 23 * * * /usr/bin/freshclam -quiet
EOT

	clamscan -r /tmp	 
	if [ $? -ne 0 ]; then
		log "ERROR" "ClamAV installation failed using yum tool"
	else
		log "INFO" "ClamAV installation  succeeded using yum tool"
	fi
	
else
log "ERROR" "OS Patching Failed"
fi
 
}
antivirusInst