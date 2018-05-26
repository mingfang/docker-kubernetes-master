#!/bin/bash

echo "Stopping Docker..."
systemctl stop docker

echo "Make sure Fan Networking is installed."
echo "apt-get update && apt-get install -y ubuntu-fan"
echo 

# Find primary interface 
PRIMARY=`ip route get 1 | awk '{print $7;exit}'`
UNDERLAY="${PRIMARY}/16"
OVERLAY="250.0.0.0/8"
IFS=. read ip1 ip2 ip3 ip4 <<< "$PRIMARY"
DOCKER_CIDR="250.$ip3.$ip4.0/24"
DOCKER_BRIDGE=kbr0

# Fan bridge
fanctl down -e
fanctl up -u $UNDERLAY -o $OVERLAY --bridge=$DOCKER_BRIDGE
fanctl show
ip link set ftun0 arp off
ip link show
rm -r /var/lib/docker/network/files/local-kv.db

# Restart Docker daemon to use the new DOCKER_BRIDGE
ZFS=$([ `df --output=fstype /var/lib/docker|tail -1` == "zfs" ] && echo "--storage-driver=zfs" || echo  "")
DOCKER_OPTS="--bridge=kbr0 --fixed-cidr=$DOCKER_CIDR --mtu=1450 --insecure-registry=0.0.0.0/0 $ZFS"

#/etc/systemd/system/docker.service.d/docker.conf
mkdir -p /etc/systemd/system/docker.service.d
printf "[Service]\nExecStart=\nExecStart=/usr/bin/dockerd $DOCKER_OPTS" > /etc/systemd/system/docker.service.d/docker.conf

echo "Restarting Docker..."
systemctl daemon-reload
systemctl restart docker --ignore-dependencies

echo "PRIMARY=$PRIMARY"
echo "UNDERLAY=$UNDERLAY"
echo "OVERLAY=$OVERLAY"
echo "DOCKER_CIDR=$DOCKER_CIDR"
echo "DOCKER_BRIDGE=$DOCKER_BRIDGE"
echo "DOCKER_OPTS=$DOCKER_OPTS"
