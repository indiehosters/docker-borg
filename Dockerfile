FROM debian

ENV BORG_VERSION=1.1.7 \
    LANG=C.UTF-8

RUN set -x \
  && apt-get update \
  && apt-get install -y gnupg2 software-properties-common apt-transport-https ca-certificates curl\
  && curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - \
  && add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable" \
  && apt-get update \
  && apt-get install -y \
    docker-ce \
    openssh-server \
    python3-pip \
    build-essential \
    libssl-dev \
    liblz4-dev \
    liblz4-1 \
    libacl1-dev \
    libacl1 \
  && rm -f /etc/ssh/ssh_host_* \
  && pip3 install borgbackup==$BORG_VERSION \
  && apt-get remove -y --purge build-essential libssl-dev liblz4-dev libacl1-dev \
  && apt-get autoremove -y --purge \
  && rm -rf /var/lib/apt/lists/* \
  && adduser --uid 500 --disabled-password --gecos "Borg Backup" --quiet borg \
  && mkdir /var/run/sshd \
  && mkdir /home/borg/.ssh \
  && chmod 700 /home/borg/.ssh \
  && chown borg:borg /home/borg/.ssh
COPY cron /usr/local/bin/
COPY authorized_keys.sample /home/borg/authorized_keys.sample
COPY entrypoint.sh /entrypoint.sh
COPY clean.sh /clean.sh
RUN curl -L https://github.com/docker/compose/releases/download/1.21.0/docker-compose-Linux-x86_64 > /usr/local/bin/docker-compose \
&& chmod +x /usr/local/bin/docker-compose

ENTRYPOINT /entrypoint.sh
