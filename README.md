# docker-kubernetes-master
Runs Kubernetes Master Inside Docker

Includes apiserver, controller-manager, scheduler, etcd and SkyDNS.

Use ```./build``` to build the Docker image.

Use ```./run``` to run the container.

Test DNS by running ```dig kubernetes.skydns.local @localhost```

The companion Dockerfile to run Nodes is here [https://github.com/mingfang/docker-kubernetes-node]
