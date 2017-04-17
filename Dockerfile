FROM ubuntu:16.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    TERM=xterm
RUN echo "export > /etc/envvars" >> /root/.bashrc && \
    echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" | tee -a /root/.bashrc /etc/bash.bashrc && \
    echo "alias tcurrent='tail /var/log/*/current -f'" | tee -a /root/.bashrc /etc/bash.bashrc

RUN apt-get update
RUN apt-get install -y locales && locale-gen en_US en_US.UTF-8

# Runit
RUN apt-get install -y --no-install-recommends runit
CMD export > /etc/envvars && /usr/sbin/runsvdir-start

# Utilities
RUN apt-get install -y --no-install-recommends vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc iproute python ssh rsync

#Etcd
RUN wget -O - https://github.com/coreos/etcd/releases/download/v3.1.5/etcd-v3.1.5-linux-amd64.tar.gz | tar zx
RUN mv /etcd* /etcd && \
    ln -s /etcd/etcd /usr/local/bin/etcd && \
    ln -s /etcd/etcdctl /usr/local/bin/etcdctl
RUN mkdir -p /var/lib/etcd-data

#Kubernetes
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/kube-apiserver
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/kube-controller-manager
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/kube-scheduler
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kube*

#Influxdb
RUN wget https://dl.influxdata.com/influxdb/releases/influxdb_1.2.2_amd64.deb && \
    dpkg -i influxdb*.deb && \
    rm influxdb*.deb

#Security
RUN mkdir -p /srv/kubernetes
COPY openssl.cnf /srv/kubernetes/
RUN openssl genrsa -out /srv/kubernetes/ca.key 2048 && \
    openssl req -x509 -new -nodes -key /srv/kubernetes/ca.key -subj "/CN=kube-ca" -days 10000 -out /srv/kubernetes/ca.crt && \
    openssl genrsa -out /srv/kubernetes/server.key 2048 && \
    openssl req -new -key /srv/kubernetes/server.key -subj "/CN=kube-apiserver" -out /srv/kubernetes/server.csr -config /srv/kubernetes/openssl.cnf && \
    openssl x509 -req -in /srv/kubernetes/server.csr -CA /srv/kubernetes/ca.crt -CAkey /srv/kubernetes/ca.key -CAcreateserial -out /srv/kubernetes/server.crt -days 10000 -extensions v3_req -extfile /srv/kubernetes/openssl.cnf
RUN TOKEN=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 | tr -d "=+/" | dd bs=32 count=1 2>/dev/null) && \
    mkdir -p /srv/kube-apiserver && \
    echo "${TOKEN},kubelet,kubelet" > /srv/kube-apiserver/known_tokens.csv

ENV SERVICE_ACCOUNT_KEY=/etc/kube-serviceaccount.key
RUN openssl genrsa -out "${SERVICE_ACCOUNT_KEY}" 2048 2>/dev/null
ENV KUBERNETES_SERVICE_HOST=localhost KUBERNETES_SERVICE_PORT=443

#Heapster
COPY heapster /heapster

#Scheduler Policy
COPY scheduler-policy.json /etc/

# Add runit services
COPY sv /etc/service 
ARG BUILD_INFO
LABEL BUILD_INFO=$BUILD_INFO
