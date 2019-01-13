#!/bin/bash
set -e

# VAULT_TOKEN=$(grep "token " /dev/shm/kubernetes/KUBELET_TOKEN | awk '{print $2}') ROLE=kubelet CN=kubelet bash -x consul-template.sh

cat <<EOF >/tmp/${ROLE}-ca.tpl
{{ with secret "kubernetes/issue/${ROLE}" "common_name=${CN}" "alt_names=${ALT_NAMES}" "ip_sans=${IP_SANS}" "ttl=${TTL}" }}
{{ .Data.issuing_ca }}{{ end }}
EOF

cat <<EOF >/tmp/${ROLE}-cert.tpl
{{ with secret "kubernetes/issue/${ROLE}" "common_name=${CN}" "alt_names=${ALT_NAMES}" "ip_sans=${IP_SANS}" "ttl=${TTL}" }}
{{ .Data.certificate }}{{ end }}
EOF

cat <<EOF >/tmp/${ROLE}-key.tpl
{{ with secret "kubernetes/issue/${ROLE}" "common_name=${CN}" "alt_names=${ALT_NAMES}" "ip_sans=${IP_SANS}" "ttl=${TTL}" }}
{{ .Data.private_key }}{{ end }}
EOF

cat <<EOF >/tmp/${ROLE}.hcl
template {
  source      = "/tmp/${ROLE}-cert.tpl"
  destination = "/dev/shm/kubernetes/${ROLE}-cert.pem"
}

template {
  source      = "/tmp/${ROLE}-ca.tpl"
  destination = "/dev/shm/kubernetes/${ROLE}-ca.pem"
}

template {
  source      = "/tmp/${ROLE}-key.tpl"
  destination = "/dev/shm/kubernetes/${ROLE}-key.pem"
  command     = "${COMMAND}"
}
EOF

consul-template \
  -config=/tmp/${ROLE}.hcl \
  -vault-retry-attempts=5 \
  -log-level=info \
  -vault-ssl-verify=false \
  -vault-renew-token=true \
  -vault-token=${VAULT_TOKEN}
