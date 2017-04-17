#!/bin/bash -eux

if [ ${BORG_MODE} = "SERVER" ]; then
  dpkg-reconfigure openssh-server
  chown borg:borg /home/borg/.ssh/authorized_keys
  exec /usr/sbin/sshd -D
else
  export BORG_REPO
  DEFAULT_ARCHIVE="${HOSTNAME}_$(date +%Y-%m-%d)"
  ARCHIVE="${ARCHIVE:-$DEFAULT_ARCHIVE}"

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
    COMPRESSION=''
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

	if [ -n "${PRUNE_PREFIX:-}" ]; then
		PRUNE_PREFIX="--prefix=${PRUNE_PREFIX}"
	else
		PRUNE_PREFIX=''
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
    cd /domains
    for domain in `ls .`
    do
      echo $domain
      cd /domains/$domain
      if [ -f ./scripts/pre-backup ]
      then
        ./scripts/pre-backup
      fi
      borg create -v --stats --show-rc $COMPRESSION $EXCLUDE_BORG ::"$ARCHIVE" /to_backup
    done
    if [ -n "${PRUNE:-}" ]; then
      borg prune -v --stats --show-rc $PRUNE_PREFIX --keep-daily=$KEEP_DAILY --keep-weekly=$KEEP_WEEKLY --keep-monthly=$KEEP_MONTHLY
    fi
    borg check -v --show-rc
    sleep ${BACKUP_FREQUENCY}
  done
fi
