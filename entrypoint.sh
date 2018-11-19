#!/bin/bash -eux

export PROM_FILE=/textfiles/backup.prom

function calc_bytes {
  NUM=$1
  UNIT=$2

  case "$UNIT" in
  B)
    echo $NUM
    ;;
  kB)
    echo $NUM | awk '{ print $1 * 1024 }'
    ;;
  MB)
    echo $NUM | awk '{ print $1 * 1024 * 1024 }'
    ;;
  GB)
    echo $NUM | awk '{ print $1 * 1024 * 1024 * 1024 }'
    ;;
  TB)
    echo $NUM | awk '{ print $1 * 1024 * 1024 * 1024 * 1024 }'
    ;;
  esac
}

function prom_text {
  COUNTER=$(borg list | wc -l)
  BORG_INFO=$(borg info ::$ARCHIVE)

  # byte size
  LAST_SIZE=$(calc_bytes $(echo "$BORG_INFO" |grep "This archive" |awk '{print $3}') $(echo "$BORG_INFO" |grep "This archive" |awk '{print $4}'))
  LAST_SIZE_COMPRESSED=$(calc_bytes $(echo "$BORG_INFO" |grep "This archive" |awk '{print $5}') $(echo "$BORG_INFO" |grep "This archive" |awk '{print $6}'))
  LAST_SIZE_DEDUP=$(calc_bytes $(echo "$BORG_INFO" |grep "This archive" |awk '{print $7}') $(echo "$BORG_INFO" |grep "This archive" |awk '{print $8}'))
  TOTAL_SIZE=$(calc_bytes $(echo "$BORG_INFO" |grep "All archives" |awk '{print $3}') $(echo "$BORG_INFO" |grep "All archives" |awk '{print $4}'))
  TOTAL_SIZE_COMPRESSED=$(calc_bytes $(echo "$BORG_INFO" |grep "All archives" |awk '{print $5}') $(echo "$BORG_INFO" |grep "All archives" |awk '{print $6}'))
  TOTAL_SIZE_DEDUP=$(calc_bytes $(echo "$BORG_INFO" |grep "All archives" |awk '{print $7}') $(echo "$BORG_INFO" |grep "All archives" |awk '{print $8}'))

  echo "backup_count{host=\"$domain\"} $COUNTER" >> $PROM_FILE
  echo "backup_files{host=\"$domain\"} $(echo "$BORG_INFO" | grep "Number of files" | awk '{print $4}')" >> $PROM_FILE
  echo "backup_chunks_unique{host=\"$domain\"} $(echo "$BORG_INFO" | grep "Chunk index" | awk '{print $3}')" >> $PROM_FILE
  echo "backup_chunks_total{host=\"$domain\"} $(echo "$BORG_INFO" | grep "Chunk index" | awk '{print $4}')" >> $PROM_FILE
  echo "backup_last_size{host=\"$domain\"} $LAST_SIZE" >> $PROM_FILE
  echo "backup_last_size_compressed{host=\"$domain\"} $LAST_SIZE_COMPRESSED" >> $PROM_FILE
  echo "backup_last_size_dedup{host=\"$domain\"} $LAST_SIZE_DEDUP" >> $PROM_FILE
  echo "backup_total_size{host=\"$domain\"} $TOTAL_SIZE" >> $PROM_FILE
  echo "backup_total_size_compressed{host=\"$domain\"} $TOTAL_SIZE_COMPRESSED" >> $PROM_FILE
  echo "backup_total_size_dedup{host=\"$domain\"} $TOTAL_SIZE_DEDUP" >> $PROM_FILE
}

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
    KEEP_HOURLY=10
  fi
  if [ -z "${KEEP_DAILY:-}" ]; then
    KEEP_DAILY=30
  fi
  if [ -z "${KEEP_WEEKLY:-}" ]; then
    KEEP_WEEKLY=10
  fi
  if [ -z "${KEEP_MONTHLY:-}" ]; then
    KEEP_MONTHLY=12
  fi

  echo "backup_starting_time $(date +%s)" > $PROM_FILE
  export ARCHIVE="${HOSTNAME}_$(date +%Y-%m-%d-%H-%M)"
  cd /domains
  for domain in `ls .`
  do
    export BORG_REPO=${BORG_FOLDER}/${domain}
    export domain=${domain}
    export LAST_BACKUP_DATE=`borg list | tail -n1 | cut -d',' -f2 | cut -d" " -f2`
    if [ `date +%F` == $LAST_BACKUP_DATE ]; then
      echo "Backing up ${domain} in ${BORG_REPO}"
      cd /domains/${domain}
      if [ -f ./scripts/pre-backup ]
      then
        ./scripts/pre-backup
      fi
      borg init || true
      borg create -v --stats --show-rc $COMPRESSION $EXCLUDE_BORG ::"$ARCHIVE" .
      borg prune -v --stats --show-rc --keep-hourly=$KEEP_HOURLY --keep-daily=$KEEP_DAILY --keep-weekly=$KEEP_WEEKLY --keep-monthly=$KEEP_MONTHLY
      prom_text
    fi
  done
  echo "backup_ending_time $(date +%s)" >> $PROM_FILE
fi
