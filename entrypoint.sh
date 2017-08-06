#!/bin/bash -eux

if [ ${BORG_MODE} = "SERVER" ]; then
  if [ -n "${SSH_KEY:-}" ]; then
    dpkg-reconfigure openssh-server
    sed -i \
      -e 's/^#PasswordAuthentication yes$/PasswordAuthentication no/g' \
      -e 's/^PermitRootLogin without-password$/PermitRootLogin no/g' \
      /etc/ssh/sshd_config
    sed -e "s#SSH_KEY#${SSH_KEY}#g" /home/borg/authorized_keys.sample > /home/borg/.ssh/authorized_keys
    chown borg:borg /home/borg/.ssh/authorized_keys
    exec /usr/sbin/sshd -D
  else
    echo "You need to give an SSH_KEY env variable"
    quit
  fi
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

  if [ -z "${KEEP_HOURLY:-}" ]; then
    KEEP_DAILY=48
  fi
  if [ -z "${KEEP_DAILY:-}" ]; then
    KEEP_DAILY=14
  fi
  if [ -z "${KEEP_WEEKLY:-}" ]; then
    KEEP_WEEKLY=10
  fi
  if [ -z "${KEEP_MONTHLY:-}" ]; then
    KEEP_MONTHLY=12
  fi

  while true
  do
    export ARCHIVE="${HOSTNAME}_$(date +%Y-%m-%d-%H-%M)"
    cd /domains
    for domain in `ls .`
    do
      export BORG_REPO=${BORG_FOLDER}/${domain}
      export domain=${domain}
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
