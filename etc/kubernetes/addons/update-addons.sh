#!/usr/bin/env bash

wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/metrics-server/auth-delegator.yaml
wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/metrics-server/auth-reader.yaml
wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/metrics-server/metrics-apiservice.yaml
wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/metrics-server/metrics-server-deployment.yaml
wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/metrics-server/metrics-server-service.yaml
wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/metrics-server/resource-reader.yaml

wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns-horizontal-autoscaler/dns-horizontal-autoscaler.yaml

wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/coredns/coredns.yaml.sed -O coredns.yaml
wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/node-problem-detector/npd.yaml

#rbac/kubelet-api-auth/
wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/rbac/kubelet-api-auth/kubelet-api-admin-role.yaml
wget --backups=1 https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/rbac/kubelet-api-auth/kube-apiserver-kubelet-api-admin-binding.yaml

rm *1
