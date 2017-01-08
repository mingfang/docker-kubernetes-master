FROM ubuntu:16.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    TERM=xterm
RUN locale-gen en_US en_US.UTF-8
RUN echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" >> /root/.bashrc
RUN echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" >> /etc/bash.bashrc
RUN apt-get update

# Runit
RUN apt-get install -y --no-install-recommends runit
CMD export > /etc/envvars && /usr/sbin/runsvdir-start
RUN echo 'export > /etc/envvars' >> /root/.bashrc

# Utilities
RUN apt-get install -y --no-install-recommends vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc iproute python ssh

#Etcd
RUN wget -O - https://github.com/coreos/etcd/releases/download/v3.0.15/etcd-v3.0.15-linux-amd64.tar.gz | tar zx
RUN mv /etcd* /etcd && \
    ln -s /etcd/etcd /usr/local/bin/etcd && \
    ln -s /etcd/etcdctl /usr/local/bin/etcdctl
RUN mkdir -p /var/lib/etcd-data

#Kubernetes
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.5.1/bin/linux/amd64/kube-apiserver
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.5.1/bin/linux/amd64/kube-controller-manager
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.5.1/bin/linux/amd64/kube-scheduler
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.5.1/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kube*

#Influxdb
RUN wget https://dl.influxdata.com/influxdb/releases/influxdb_1.1.0_amd64.deb && \
    dpkg -i influxdb*.deb && \
    rm influxdb*.deb

ENV SERVICE_ACCOUNT_KEY=/etc/kube-serviceaccount.key
RUN openssl genrsa -out "${SERVICE_ACCOUNT_KEY}" 2048 2>/dev/null

#Heapster
COPY heapster /heapster

#Scheduler Policy
COPY scheduler-policy.json /etc/

# Add runit services
COPY sv /etc/service 
ARG BUILD_INFO
LABEL BUILD_INFO=$BUILD_INFO
