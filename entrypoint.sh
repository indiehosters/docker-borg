#!/bin/bash -eux

if [ ${BORG_MODE} = "SERVER" ]; then
  sed -i \
    -e 's/^#PasswordAuthentication yes$/PasswordAuthentication no/g' \
    -e 's/^PermitRootLogin without-password$/PermitRootLogin no/g' \
    /etc/ssh/sshd_config
  dpkg-reconfigure openssh-server
  chown borg:borg /home/borg/.ssh/authorized_keys
  exec /usr/sbin/sshd -D
else
  if [ -n "${EXTRACT_TO:-}" ]; then
    mkdir -p "$EXTRACT_TO"
    cd "$EXTRACT_TO"
    borg extract -v --list --show-rc ::"$ARCHIVE" ${EXTRACT_WHAT:-}
    quit
  fi

  if [ -n "${BORG_PARAMS:-}" ]; then
    borg $BORG_PARAMS
    quit
  fi

  if [ -n "${COMPRESSION:-}" ]; then
    COMPRESSION="--compression=${COMPRESSION}"
  else
    COMPRESSION='--compression=zlib,5'
  fi

  if [ -n "${EXCLUDE:-}" ]; then
    OLD_IFS=$IFS
    IFS=';'
    EXCLUDE_BORG=''
    for i in $EXCLUDE; do
        EXCLUDE_BORG="${EXCLUDE_BORG} --exclude ${i}"
    done
    IFS=$OLD_IFS
  else
    EXCLUDE_BORG=''
  fi

  if [ -z "${KEEP_DAILY:-}" ]; then
    KEEP_DAILY=7
  fi
  if [ -z "${KEEP_WEEKLY:-}" ]; then
    KEEP_WEEKLY=4
  fi
  if [ -z "${KEEP_MONTHLY:-}" ]; then
    KEEP_MONTHLY=6
  fi

  while true
  do
    ARCHIVE="${HOSTNAME}_$(date +%Y-%m-%d-%H-%M)"
    cd /domains
    for domain in `ls .`
    do
      export BORG_REPO=${BORG_FOLDER}/${domain}
      echo "Backing up ${domain} in ${BORG_REPO}"
      cd /domains/${domain}
      if [ -f ./scripts/pre-backup ]
      then
        ./scripts/pre-backup
      fi
      borg init || true
      borg create -v --stats --show-rc $COMPRESSION $EXCLUDE_BORG ::"$ARCHIVE" .
    done
    borg prune -v --stats --show-rc --keep-daily=$KEEP_DAILY --keep-weekly=$KEEP_WEEKLY --keep-monthly=$KEEP_MONTHLY
    borg check -v --show-rc
    sleep ${BACKUP_FREQUENCY}
  done
fi
