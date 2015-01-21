FROM ubuntu:14.04
 
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
RUN locale-gen en_US en_US.UTF-8
ENV LANG en_US.UTF-8

#Runit
RUN apt-get install -y runit 
CMD export > /etc/envvars && /usr/sbin/runsvdir-start
RUN echo 'export > /etc/envvars' >> /root/.bashrc

#Utilities
RUN apt-get install -y vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common

#Etcd
RUN curl -L https://github.com/coreos/etcd/releases/download/v0.4.6/etcd-v0.4.6-linux-amd64.tar.gz | tar zx
RUN mv /etcd* /etcd && \
    ln -s /etcd/etcd /usr/local/bin/etcd && \
    ln -s /etcd/etcdctl /usr/local/bin/etcdctl

#Kubernetes
RUN curl -L https://github.com/GoogleCloudPlatform/kubernetes/releases/download/v0.9.0/kubernetes.tar.gz | tar zx
RUN tar -xvf /kubernetes/server/kubernetes-server-linux-amd64.tar.gz --strip-components 3 -C /usr/local/bin 

#Required to build SkyDNS
RUN apt-get install -y mercurial golang-go
ENV GOPATH /tmp

#SkyDNS
RUN go get github.com/skynetservices/skydns && \
    cd $GOPATH/src/github.com/skynetservices/skydns && \
    go build -v && \
    mv skydns /usr/local/bin

#Aliases
ADD aliases /root/.aliases
RUN echo "source ~/.aliases" >> /root/.bashrc

#Add runit services
ADD sv /etc/service 

