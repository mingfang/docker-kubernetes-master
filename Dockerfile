FROM ubuntu:14.04
 
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
RUN locale-gen en_US en_US.UTF-8
ENV LANG en_US.UTF-8
RUN echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" >> /root/.bashrc

#Runit
RUN apt-get install -y runit 
CMD export > /etc/envvars && /usr/sbin/runsvdir-start
RUN echo 'export > /etc/envvars' >> /root/.bashrc

#Utilities
RUN apt-get install -y vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc

#Etcd
RUN wget -O - https://github.com/coreos/etcd/releases/download/v2.2.2/etcd-v2.2.2-linux-amd64.tar.gz | tar zx
RUN mv /etcd* /etcd && \
    ln -s /etcd/etcd /usr/local/bin/etcd && \
    ln -s /etcd/etcdctl /usr/local/bin/etcdctl
RUN mkdir -p /var/lib/etcd-data

#Kubernetes
RUN wget -O - https://github.com/kubernetes/kubernetes/releases/download/v1.1.3/kubernetes.tar.gz | tar zx
RUN tar -xvf /kubernetes/server/kubernetes-server-linux-amd64.tar.gz --strip-components 3 -C /usr/local/bin 

#Node
RUN wget -O - http://nodejs.org/dist/v0.12.7/node-v0.12.7-linux-x64.tar.gz | tar xz
RUN mv node* node && \
    ln -s /node/bin/node /usr/local/bin/node && \
    ln -s /node/bin/npm /usr/local/bin/npm
ENV NODE_PATH /usr/local/lib/node_modules

#cmdgateway
COPY cmdgateway/package.json /cmdgateway/package.json
RUN cd /cmdgateway && \
    npm install
COPY cmdgateway /cmdgateway

#Aliases
COPY aliases /root/.aliases
RUN echo "source ~/.aliases" >> /root/.bashrc

#Scheduler Policy
COPY scheduler-policy.json /etc/

#Add runit services
COPY sv /etc/service 

