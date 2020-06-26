#!/bin/bash

# http://stackoverflow.com/a/246128/920350
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE=$DIR/log
IP_FILE=$DIR/current.ip

# Load sensitive stuff from env file. Exposes:
#   ZONE_ID
#   RECORDSET
source $DIR/.env

# Additional DNS recordset options
TTL=300
COMMENT="Update via PorgyPi - $(date)"
# Set to AAAA if using IPv6 addressing
TYPE="A"

#
# Write a log message
#
function log_msg {
	local MSG=$1
	local TS=$(date +"%F %T")
	[[ -f $LOG_FILE ]] || touch $LOG_FILE
	echo "[$TS] - $1" >> $LOG_FILE
}

#
# Validate an IPv4 address
#
function is_valid {
	local ADDR=$1
	local STATUS=1

	if [[ $ADDR =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		local OIFS=$IFS
		IFS='.'
		ADDR=($ADDR)
		IFS=$OIFS
		[[ ${ADDR[0]} -le 255 && ${ADDR[1]} -le 255 && ${ADDR[2]} -le 255 && ${ADDR[3]} -le 255 ]]
		STATUS=$?
	fi

	return $STATUS
}

# Load and validate IP
IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
if ! is_valid $IP; then
	log_msg "Invalid IP address: $IP"
	exit 1
fi

# Check for changes and bail if it hasn't
[[ -f $IP_FILE ]] || touch $IP_FILE
if grep -Fxq "$IP" $IP_FILE; then
	log_msg "IP not changed"
	exit 0
fi

# Write a Route 53 payload to a temp file
TMPFILE=$(mktemp)
cat > $TMPFILE << EOF
{
  "Comment": "$COMMENT",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "ResourceRecords": [{ "Value": "$IP" }],
        "Name": "$RECORDSET",
        "Type": "$TYPE",
        "TTL": $TTL
      }
    }
  ]
}
EOF

# Send to AWS
log_msg "Sending update to Route 53:"
aws route53 change-resource-record-sets \
	--hosted-zone-id $ZONE_ID \
	--change-batch file://$TMPFILE >> $LOG_FILE
echo >> $LOG_FILE

rm $TMPFILE

# Cache IP for next run
echo "$IP" > $IP_FILE

