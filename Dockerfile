FROM ubuntu:16.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    TERM=xterm
RUN locale-gen en_US en_US.UTF-8
RUN echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" | tee -a /root/.bashrc /etc/bash.bashrc
RUN apt-get update

# Runit
RUN apt-get install -y --no-install-recommends runit
CMD export > /etc/envvars && /usr/sbin/runsvdir-start
RUN echo 'export > /etc/envvars' >> /root/.bashrc
RUN echo "alias tcurrent='tail /var/log/*/current -f'" | tee -a /root/.bashrc /etc/bash.bashrc

# Utilities
RUN apt-get install -y --no-install-recommends vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc iproute python ssh rsync

#Etcd
RUN wget -O - https://github.com/coreos/etcd/releases/download/v3.1.4/etcd-v3.1.4-linux-amd64.tar.gz | tar zx
RUN mv /etcd* /etcd && \
    ln -s /etcd/etcd /usr/local/bin/etcd && \
    ln -s /etcd/etcdctl /usr/local/bin/etcdctl
RUN mkdir -p /var/lib/etcd-data

#Kubernetes
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.5.5/bin/linux/amd64/kube-apiserver
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.5.5/bin/linux/amd64/kube-controller-manager
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.5.5/bin/linux/amd64/kube-scheduler
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.5.5/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kube*

#Influxdb
RUN wget https://dl.influxdata.com/influxdb/releases/influxdb_1.2.0_amd64.deb && \
    dpkg -i influxdb*.deb && \
    rm influxdb*.deb

#Security
RUN mkdir -p /srv/kubernetes
RUN openssl genrsa -out /srv/kubernetes/ca.key 4096 && \
    openssl req -x509 -new -nodes -key /srv/kubernetes/ca.key -subj "/CN=*/" -days 10000 -out /srv/kubernetes/ca.crt && \
    openssl genrsa -out /srv/kubernetes/server.key 2048 && \
    openssl req -new -key /srv/kubernetes/server.key -subj "/CN=*/" -out /srv/kubernetes/server.csr && \
    openssl x509 -req -in /srv/kubernetes/server.csr -CA /srv/kubernetes/ca.crt -CAkey /srv/kubernetes/ca.key -CAcreateserial -out /srv/kubernetes/server.crt -days 10000
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
