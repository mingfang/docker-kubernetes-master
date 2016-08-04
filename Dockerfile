FROM ubuntu:16.04
  
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    TERM=ansi
RUN locale-gen en_US en_US.UTF-8
RUN echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" >> /root/.bashrc
RUN apt-get update

# Runit
RUN apt-get install -y runit 
CMD export > /etc/envvars && /usr/sbin/runsvdir-start
RUN echo 'export > /etc/envvars' >> /root/.bashrc

# Utilities
RUN apt-get install -y vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc

#Etcd
RUN wget -O - https://github.com/coreos/etcd/releases/download/v2.3.6/etcd-v2.3.6-linux-amd64.tar.gz | tar zx
RUN mv /etcd* /etcd && \
    ln -s /etcd/etcd /usr/local/bin/etcd && \
    ln -s /etcd/etcdctl /usr/local/bin/etcdctl
RUN mkdir -p /var/lib/etcd-data

#Kubernetes
RUN wget -O - https://github.com/kubernetes/kubernetes/releases/download/v1.3.3/kubernetes.tar.gz | tar zx
RUN tar -xvf /kubernetes/server/kubernetes-server-linux-amd64.tar.gz --strip-components 3 -C /usr/local/bin 

#Aliases
COPY aliases /root/.aliases
RUN echo "source ~/.aliases" >> /root/.bashrc

#Scheduler Policy
COPY scheduler-policy.json /etc/

# Add runit services
COPY sv /etc/service 
ARG BUILD_INFO
LABEL BUILD_INFO=$BUILD_INFO
