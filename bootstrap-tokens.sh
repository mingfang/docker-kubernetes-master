#!/usr/bin/env bash

TTL=1m

KUBELET_TOKEN=$(vault token create -orphan -ttl=$TTL -wrap-ttl=$TTL -field=wrapping_token -role=kubelet)
PROXY_TOKEN=$(vault token create -orphan -ttl=$TTL -wrap-ttl=$TTL -field=wrapping_token -role=proxy)

echo "KUBELET_TOKEN=$KUBELET_TOKEN PROXY_TOKEN=$PROXY_TOKEN ./run $HOSTNAME"
