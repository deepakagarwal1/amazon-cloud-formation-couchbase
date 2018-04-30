#!/usr/bin/env bash

echo "Running cb-bucket.sh"

adminUsername=$1
adminPassword=$2
buckets=${buckets:-"common dcms gradebook ims lec led lpb"}


echo "Using the settings:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
 

cd /opt/couchbase/bin/
  echo "Adding buckets in the cluster"
  for bucket in ${buckets} ; do
    resp_code=$(curl -s -w "%{http_code}" -u ${adminUsername}:${adminPassword} http://127.0.0.1:8091/pools/default/buckets/${bucket} -o /dev/null)
    if [ "${resp_code}" == "404" ]; then
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
    fi
  done
