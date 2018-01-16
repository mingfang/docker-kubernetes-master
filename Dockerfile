FROM ubuntu:16.04 as base

ENV DEBIAN_FRONTEND=noninteractive TERM=xterm
RUN echo "export > /etc/envvars" >> /root/.bashrc && \
    echo "export PS1='\[\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" | tee -a /root/.bashrc /etc/skel/.bashrc && \
    echo "alias tcurrent='tail /var/log/*/current -f'" | tee -a /root/.bashrc /etc/skel/.bashrc

RUN apt-get update
RUN apt-get install -y locales && locale-gen en_US.UTF-8 && dpkg-reconfigure locales
ENV LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# Runit
RUN apt-get install -y --no-install-recommends runit
CMD export > /etc/envvars && /usr/sbin/runsvdir-start

# Utilities
RUN apt-get install -y --no-install-recommends vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc iproute python ssh rsync gettext-base

#Etcd
RUN wget -O - https://github.com/coreos/etcd/releases/download/v3.2.13/etcd-v3.2.13-linux-amd64.tar.gz | tar zx
RUN mv /etcd* /etcd && \
    ln -s /etcd/etcd /usr/local/bin/etcd && \
    ln -s /etcd/etcdctl /usr/local/bin/etcdctl
RUN mkdir -p /var/lib/etcd-data

#Influxdb
RUN wget https://dl.influxdata.com/influxdb/releases/influxdb_1.4.2_amd64.deb && \
    dpkg -i influxdb*.deb && \
    rm influxdb*.deb

#Vault
RUN wget https://releases.hashicorp.com/vault/0.8.3/vault_0.8.3_linux_amd64.zip && \
    unzip vault*.zip && \
    rm vault*.zip && \
    mv vault /usr/local/bin/

#Heapster
COPY heapster /heapster
COPY --from=gcr.io/google_containers/heapster:v1.5.0 heapster /heapster/heapster

#Rescheduler
COPY --from=gcr.io/google-containers/rescheduler:v0.3.1 rescheduler /usr/local/bin/rescheduler

#Kubernetes
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.9.1/bin/linux/amd64/kube-apiserver
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.9.1/bin/linux/amd64/kube-controller-manager
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.9.1/bin/linux/amd64/kube-scheduler
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.9.1/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kube*

#Vault
RUN mkdir -p /srv/kubernetes
COPY vault-init.sh /
COPY vault.hcl /
ENV VAULT_ADDR=http://0.0.0.0:8200

#FlexVolume
RUN mkdir -p /usr/libexec/kubernetes/kubelet-plugins/volume/exec
RUN git clone --depth=1 https://github.com/mingfang/flexvolume-ebs.git /usr/libexec/kubernetes/kubelet-plugins/volume/exec/flexvolume~ebs
RUN /usr/libexec/kubernetes/kubelet-plugins/volume/exec/flexvolume~ebs/install
RUN chmod +x /usr/libexec/kubernetes/kubelet-plugins/volume/exec/*/*

# Add runit services
COPY sv /etc/service 
ARG BUILD_INFO
LABEL BUILD_INFO=$BUILD_INFO
