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

#Proxy needs iptables
RUN apt-get install -y --no-install-recommends iptables conntrack

#Dnsmasq and Confd used for DNS
RUN apt-get install -y --no-install-recommends dnsmasq
RUN wget -O /usr/local/bin/confd  https://github.com/kelseyhightower/confd/releases/download/v0.15.0/confd-0.15.0-linux-amd64 && \
    chmod +x /usr/local/bin/confd

#ZFS
RUN apt-get install -y --no-install-recommends zfsutils-linux

#NFS client
RUN apt-get install -y nfs-common

#XFS
RUN apt-get install -y libguestfs-xfs

#Ceph client
RUN apt-get install -y ceph-common

#For Hairpin-veth mode
RUN apt-get install -y ethtool

#IPVS
RUN apt-get install -y ipvsadm ipset

#Vault
RUN wget https://releases.hashicorp.com/vault/0.10.2/vault_0.10.2_linux_amd64.zip && \
    unzip vault*.zip && \
    rm vault*.zip && \
    mv vault /usr/local/bin/

#Etcd
RUN wget -O - https://github.com/coreos/etcd/releases/download/v3.3.7/etcd-v3.3.7-linux-amd64.tar.gz | tar zx
RUN mv /etcd* /etcd && \
    ln -s /etcd/etcd /usr/local/bin/etcd && \
    ln -s /etcd/etcdctl /usr/local/bin/etcdctl
RUN mkdir -p /var/lib/etcd-data

#Kubernetes
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.11.1/bin/linux/amd64/kube-apiserver
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.11.1/bin/linux/amd64/kube-controller-manager
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.11.1/bin/linux/amd64/kube-scheduler
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.11.1/bin/linux/amd64/kubelet
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.11.1/bin/linux/amd64/kube-proxy
RUN wget -P /usr/local/bin https://storage.googleapis.com/kubernetes-release/release/v1.11.1/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kube*

#Addon Manager
COPY --from=gcr.io/google-containers/kube-addon-manager:v8.6 /opt/kube-addons.sh /opt/kube-addons.sh
COPY --from=gcr.io/google-containers/kube-addon-manager:v8.6 /opt/namespace.yaml /opt/namespace.yaml 

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

COPY etc/kubernetes/addons /etc/kubernetes/addons

# Add runit services
COPY sv /etc/service 
ARG BUILD_INFO
LABEL BUILD_INFO=$BUILD_INFO
