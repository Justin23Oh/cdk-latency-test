#!/bin/sh
target_ddb_table=$1
target_ips=""
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
az_loc=`curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/placement/availability-zone`
local_ipv4=`curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/local-ipv4`

status=''

function retrieveStatus() {
  status=`aws dynamodb get-item --table-name ${target_ddb_table} --key '{ "pk" : { "S": "CONTROL" } , "sk" : {"S" : "STATUS_KEY" } }' | jq '.Item.value.S' | sed '1,$s/"//g'` 
  if [ -z "${status}" ]
  then 
    status='STOP'
    aws dynamodb put-item --table-name ${target_ddb_table} --item '{ "pk": {"S" : "CONTROL" }, "sk" : { "S" : "STATUS_KEY" }, "value" : { "S" : "STOP" } }'
  fi
}

function retrieveIps() {
  target_ips=`aws dynamodb query --table-name ${target_ddb_table} --select ALL_ATTRIBUTES --key-condition-expression 'pk = :param1'  --expression-attribute-values '{ ":param1" : { "S" : "IP"}}' | jq '.Items | .[].sk.S' | sed '1,$s/"//g'`
}

function putLocalIp() {
  aws dynamodb put-item --table-name ${target_ddb_table} --item '{ "pk": {"S" : "IP" }, "sk" : { "S" : "'${local_ipv4}'" }, "value" : { "S" : "'${az_loc}'" } }'
}

function putPingLatency() {
  aws dynamodb put-item --table-name ${target_ddb_table} --item '{ "pk": {"S" : "SRC'$1'" }, "sk" : { "S" : "TGT'$2'" }, "result" : { "S" : "'$3'" } }'
}

function testPing() {
  for target_ipv4 in ${target_ips}
  do
    ping_result=`ping ${target_ipv4} -c 5 | grep rtt | awk '{ print $4 }'`
    putPingLatency "${local_ipv4}" "${target_ipv4}" "${ping_result}"
  done
}

putLocalIp

while(true) 
do
  retrieveStatus
  echo current status is ${status}
  sleep 1
  case "${status}" in
  START)
    echo 'Start' 
    retrieveIps
    testPing
  ;;
  STOP)
    echo 'Stop'
    sleep 5
  ;;
  TERMINATE)
    echo 'terminate'
    exit 1
  ;;
  *)
  echo "There is no matched status in DDB table (${target_ddb_table})"
  exit 1
  esac
done

echo "all process is done."

