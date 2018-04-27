#!/usr/bin/env bash

echo "Running cb-bucket.sh"

adminUsername=$1
adminPassword=$2
buckets=${buckets:-"common dcms gradebook ims lec led lpb"}

if [ -z "$3" ]
then
  echo "This node is part of the autoscaling group that contains the rally point."
  rallyPrivateDNS=`getrallyPrivateDNS`
else
  rallyAutoScalingGroup=$5
  echo "This node is not the rally point and not part of the autoscaling group that contains the rally point."
  echo rallyAutoScalingGroup \'$rallyAutoScalingGroup\'
  rallyPrivateDNS=`getrallyPrivateDNS ${rallyAutoScalingGroup}`
fi

nodePrivateDNS=`curl http://169.254.169.254/latest/meta-data/hostname`

echo "Using the settings:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
echo rallyPrivateDNS \'$rallyPrivateDNS\'
echo nodePrivateDNS \'$nodePrivateDNS\'

cd /opt/couchbase/bin/

if [[ $rallyPrivateDNS == $nodePrivateDNS ]]
then

  echo "Adding buckets in the cluster"
  for bucket in ${buckets} ; do
    echo "Configuring bucket ${bucket}..."
       /opt/couchbase/bin/couchbase-cli bucket-create \
      --cluster 127.0.0.1:8091 \
      --bucket="${bucket}" \
      --bucket-type=couchbase \
      --bucket-ramsize=512 \
      --bucket-replica=1 \
      --wait \
      --username ${adminUsername} \
      --password ${adminPassword};
      if [ "$?" == "0" ]; then
        echo "Created bucket ${bucket}"
      else
        echo "Some issue with Creating bucket ${bucket}"
      fi
      # Create primary index
      echo "Creating index for ${bucket}"
      /opt/couchbase/bin/cbq -u ${adminUsername} -p ${adminPassword} --script="CREATE PRIMARY INDEX ${bucket} ON ${bucket}";
      if [ "$?" == "0" ]; then
        echo "Created index for ${bucket}"
      else
        echo "Some issue with Creating index for ${bucket}"
      fi
  done
fi
