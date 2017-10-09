#!/bin/bash

vault server -config=/vault.hcl&
sleep 3
VAULT_DATA=/var/lib/vault-data

if ! vault init -check; then
    echo "Initializing Vault..."
    vault init > $VAULT_DATA/VAULT_INIT
fi

#Unseal
grep "Unseal Key" $VAULT_DATA/VAULT_INIT | awk '{print $4}' | xargs -I {} vault unseal {}

#auth as root
grep "Root Token" $VAULT_DATA/VAULT_INIT | awk '{print $4}' | xargs -I {} vault auth {}
vault audit-enable file file_path=/var/log/vault_audit.log

#init CA
vault mount -path kubernetes pki
vault mount-tune -max-lease-ttl=87600h kubernetes

#generate root certificate
vault write kubernetes/root/generate/internal common_name=kubernetes ttl=87600h

#api-server pki role
vault write kubernetes/roles/kube-apiserver allow_any_name=true enforce_hostnames=false max_ttl="720h"

#kubelet pki role
vault write kubernetes/roles/kubelet allow_any_name=true enforce_hostnames=false organization="system:nodes" max_ttl="720h"

#kube-proxy pki role
vault write kubernetes/roles/kube-proxy allow_any_name=true enforce_hostnames=false max_ttl="720h"

#kube-apiserver vault policy
cat <<EOT | vault policy-write kubernetes/policy/kube-apiserver -
path "kubernetes/issue/kube-apiserver" {
  policy = "write"
}
path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT

#kubelet vault policy
cat <<EOT | vault policy-write kubernetes/policy/kubelet -
path "kubernetes/issue/kubelet" {
  policy = "write"
}

path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT

#kube-proxy vault policy
cat <<EOT | vault policy-write kubernetes/policy/kube-proxy -
path "kubernetes/issue/kube-proxy" {
  policy = "write"
}
path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT

#kube-apiserver auth role
vault write auth/token/roles/kube-apiserver period="720h" orphan=true allowed_policies="kubernetes/policy/kube-apiserver"

#kubelet auth role
vault write auth/token/roles/kubelet period="720h" orphan=true allowed_policies="kubernetes/policy/kubelet"

#kube-proxy auth role
vault write auth/token/roles/kube-proxy period="720h" orphan=true allowed_policies="kubernetes/policy/kube-proxy"

#service account secret key
#openssl genrsa 4096 > $VAULT_DATA/service-account-key
#vault write secret/kubernetes/service-account-key key=@$VAULT_DATA/service-account-key
#rm $VAULT_DATA/service-account-key

if $VPC_ID; then
#enable AWS integration
vault auth-enable aws

#vault aws policy
cat <<EOT | vault policy-write aws/policy/knode -
path "secret/aws/*" {
  policy = "write"
}
path "auth/aws/login" {
  policy = "write"
}
EOT
#knode aws role
vault write auth/aws/role/knode auth_type=ec2 bound_vpc_id="$VPC_ID" policies="aws/policy/knode,kubernetes/policy/kubelet,kubernetes/policy/kube-proxy"
fi

#setup token for kmaster
vault token-create -role="kube-apiserver" > /dev/shm/KMASTER_TOKEN

