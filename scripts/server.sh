#!/usr/bin/env bash

echo "Running server.sh"

adminUsername=$1
adminPassword=$2
services=$3
stackName=$4

source util.sh
formatDataDisk

yum -y update
yum -y install jq

if [ -z "$5" ]
then
  echo "This node is part of the autoscaling group that contains the rally point."
  rallyPrivateDNS=`getrallyPrivateDNS`
else
  rallyAutoScalingGroup=$5
  echo "This node is not the rally point and not part of the autoscaling group that contains the rally point."
  echo rallyAutoScalingGroup \'$rallyAutoScalingGroup\'
  rallyPrivateDNS=`getrallyPrivateDNS ${rallyAutoScalingGroup}`
fi

region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
  | jq '.region'  \
  | sed 's/^"\(.*\)"$/\1/' )

instanceID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
  | jq '.instanceId' \
  | sed 's/^"\(.*\)"$/\1/' )

nodePrivateDNS=`curl http://169.254.169.254/latest/meta-data/hostname`


echo "Using the settings:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
echo services \'$services\'
echo stackName \'$stackName\'
echo rallyPrivateDNS \'$rallyPrivateDNS\'
echo region \'$region\'
echo instanceID \'$instanceID\'
echo nodePrivateDNS \'$nodePrivateDNS\'

if [[ ${rallyPrivateDNS} == ${nodePrivateDNS} ]]
then
  aws ec2 create-tags \
    --region ${region} \
    --resources ${instanceID} \
    --tags Key=Name,Value=${stackName}-ServerRally Key=Role,Value=couchbase
else
  aws ec2 create-tags \
    --region ${region} \
    --resources ${instanceID} \
    --tags Key=Name,Value=${stackName}-Server Key=Role,Value=couchbase
fi

cd /opt/couchbase/bin/

echo "Running couchbase-cli node-init"
output=""
while [[ ! $output =~ "SUCCESS" ]]
do
  output=`./couchbase-cli node-init \
    --cluster=$nodePrivateDNS \
    --node-init-hostname=$nodePrivateDNS \
    --node-init-data-path=/mnt/datadisk/data \
    --node-init-index-path=/mnt/datadisk/index \
    --user=$adminUsername \
    --pass=$adminPassword`
  echo node-init output \'$output\'
  sleep 10
done

if [[ $rallyPrivateDNS == $nodePrivateDNS ]]
then
  totalRAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  dataRAM=$((50 * $totalRAM / 100000))
  indexRAM=$((25 * $totalRAM / 100000))

  echo "Running couchbase-cli cluster-init"
  ./couchbase-cli cluster-init \
    --cluster=$nodePrivateDNS \
    --cluster-username=$adminUsername \
    --cluster-password=$adminPassword \
    --cluster-ramsize=$dataRAM \
    --cluster-index-ramsize=$indexRAM \
    --services=${services}
else
  sudo -- sh -c "echo $(echo "$rallyPrivateDNS" | cut -d '-' -f 2,3,4,5|tr '-' '.'|cut -d '.' -f 1,2,3,4) $rallyPrivateDNS >> /etc/hosts"
  sudo -- sh -c "echo $(echo "$nodePrivateDNS" | cut -d '-' -f 2,3,4,5|tr '-' '.'|cut -d '.' -f 1,2,3,4) $nodePrivateDNS >> /etc/hosts"

  echo "Running couchbase-cli server-add"
  output=""
  while [[ $output != "Server $nodePrivateDNS:8091 added" && ! $output =~ "Node is already part of cluster." ]]
  do
    output=`./couchbase-cli server-add \
      --cluster=$rallyPrivateDNS \
      --user=$adminUsername \
      --pass=$adminPassword \
      --server-add=$nodePrivateDNS \
      --server-add-username=$adminUsername \
      --server-add-password=$adminPassword \
      --services=${services}`
    echo server-add output \'$output\'
    sleep 10
  done

  echo "Running couchbase-cli rebalance"
  output=""
  while [[ ! $output =~ "SUCCESS" ]]
  do
    output=`./couchbase-cli rebalance \
    --cluster=$rallyPrivateDNS \
    --user=$adminUsername \
    --pass=$adminPassword`
    echo rebalance output \'$output\'
    sleep 10
  done

fi
