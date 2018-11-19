#!/bin/bash -eux

if [ -z ${BORG_PASSPHRASE+x} ];
then
  echo "Please set the remote PASSPHRASE"
fi

export DATE_ONE_MONTH_AGO=`date +%Y-%m-%d -d "1 month ago"`
export DATE=${DATE_TO_DELETE:-$DATE_ONE_MONTH_AGO}

cd /backups
for domain in `ls .`
do
  export BORG_REPO=${domain}
  export ARCHIVE=`borg list | grep ${DATE} | cut -d" " -f1`
  if [ -n "$ARCHIVE" ]; then
    borg config ./${BORG_REPO}/ append_only 0
    borg delete ::${ARCHIVE}
    borg config ./${BORG_REPO}/ append_only 1
  fi
done
chown -R 500:500 /backups
