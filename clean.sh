#!/bin/bash -eux

if [ -z ${BORG_PASSPHRASE+x} ];
then
  echo "Please set the remote PASSPHRASE"
fi

export DATE_TO_DELETE=`date +%Y-%m-%d -d "1 month ago"`

cd /backups
for domain in `ls .`
do
  export BORG_REPO=${domain}
  export ARCHIVE=`borg list | grep ${DATE_TO_DELETE} | cut -d" " -f1`
  if [ -n "$ARCHIVE" ]; then
    borg delete ::${ARCHIVE}
  fi
done
