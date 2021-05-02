#!/bin/bash

# Allow mlock to avoid swapping Vault memory to disk
setcap cap_ipc_lock=+ep $(readlink -f $(which vault))

KUBERNETES_MASTER="${KUBERNETES_MASTER:-https://$HOSTNAME:$SECURE_PORT}"
HEALTH_URL="$VAULT_ADDR/v1/sys/health"
VAULT_DATA_DIR=/var/lib/vault-data
PKI_DIR=/dev/shm/kubernetes

mkdir -p $VAULT_DATA_DIR
mkdir -p $PKI_DIR

if ! curl -s $HEALTH_URL; then
  vault server -config=/vault.hcl&
fi
until curl -s $HEALTH_URL; do echo "Waiting for Vault..."; sleep 3; done

if [ ! "$(ls $VAULT_DATA_DIR)" ]; then
    vault operator init > $VAULT_DATA_DIR/VAULT_INIT
fi

#Unseal
grep "Unseal Key" $VAULT_DATA_DIR/VAULT_INIT | awk '{print $4}' | xargs -I {} vault operator unseal {}

#auth as root
grep "Root Token" $VAULT_DATA_DIR/VAULT_INIT | awk '{print $4}' | xargs -I {} vault login {}
vault audit enable file file_path=/var/log/vault_audit.log

# enable KV secrets engine
vault secrets enable -path=secret/ kv

# root CA

vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

curl -s $VAULT_ADDR/v1/pki/ca/pem --output - > $PKI_DIR/root-ca.pem
if [[ ! -s $PKI_DIR/root-ca.pem ]]; then
  vault write pki/root/generate/internal common_name="root" ttl=87600h
  curl -s $VAULT_ADDR/v1/pki/ca/pem --output - > $PKI_DIR/root-ca.pem
  vault write pki/config/urls \
    issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
    crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
fi


# intermediate CA

vault secrets enable -path=kubernetes pki
vault secrets tune -max-lease-ttl=43800h kubernetes

curl -s $VAULT_ADDR/v1/kubernetes/ca_chain --output - > $PKI_DIR/kubernetes-ca.pem
if [[ ! -s $PKI_DIR/kubernetes-ca.pem ]]; then
  vault write -format=json kubernetes/intermediate/generate/internal \
    common_name="kubernetes-ca"  \
    | jq -r '.data.csr' > $PKI_DIR/kubernetes.csr
  vault write -format=json pki/root/sign-intermediate ttl="43800h" format=pem_bundle csr=@$PKI_DIR/kubernetes.csr \
    | jq -r '.data.certificate' > $PKI_DIR/kubernetes-ca.pem
  cat $PKI_DIR/root-ca.pem >> $PKI_DIR/kubernetes-ca.pem
  vault write kubernetes/intermediate/set-signed certificate=@$PKI_DIR/kubernetes-ca.pem
  rm $PKI_DIR/kubernetes.csr
fi

# cluster signing CA

vault secrets enable -path=cluster-signing pki
vault secrets tune -max-lease-ttl=43800h cluster-signing

DATA=$(vault write -format=json cluster-signing/intermediate/generate/exported common_name="cluster-signing" ttl="43800h")
echo $DATA|jq -r '.data.csr' > $PKI_DIR/cluster-signing.csr
echo $DATA|jq -r '.data.private_key' > $PKI_DIR/cluster-signing-key.pem
vault write -format=json pki/root/sign-intermediate ttl="43800h" format=pem_bundle csr=@$PKI_DIR/cluster-signing.csr \
    | jq -r '.data.certificate' > $PKI_DIR/cluster-signing-ca.pem
vault write cluster-signing/intermediate/set-signed certificate=@$PKI_DIR/cluster-signing-ca.pem
rm $PKI_DIR/cluster-signing.csr

# apiserver

cat <<EOT | vault policy write kubernetes/policy/apiserver -
path "kubernetes/issue/apiserver" {
  policy = "write"
}
path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT
vault write auth/token/roles/apiserver orphan=true allowed_policies="kubernetes/policy/apiserver" period="24h"
vault write kubernetes/roles/apiserver allow_any_name=true enforce_hostnames=false max_ttl="720h" generate_lease=true


#kube-controller-manager

cat <<EOT | vault policy write kubernetes/policy/kube-controller-manager -
path "kubernetes/issue/kube-controller-manager" {
  policy = "write"
}

path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT
vault write auth/token/roles/kube-controller-manager orphan=true allowed_policies="kubernetes/policy/kube-controller-manager" period="24h"
vault write kubernetes/roles/kube-controller-manager organization="system:kube-controller-manager" allow_any_name=true enforce_hostnames=false max_ttl="720h" generate_lease=true

#kube-scheduler

cat <<EOT | vault policy write kubernetes/policy/kube-scheduler -
path "kubernetes/issue/kube-scheduler" {
  policy = "write"
}

path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT
vault write auth/token/roles/kube-scheduler orphan=true allowed_policies="kubernetes/policy/kube-scheduler" period="24h"
vault write kubernetes/roles/kube-scheduler organization="system:kube-scheduler" allow_any_name=true enforce_hostnames=false max_ttl="720h" generate_lease=true

#kubelet

cat <<EOT | vault policy write kubernetes/policy/kubelet -
path "kubernetes/issue/kubelet" {
  policy = "write"
}

path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT
vault write auth/token/roles/kubelet orphan=true allowed_policies="kubernetes/policy/kubelet" period="24h"
vault write kubernetes/roles/kubelet organization="system:nodes" allow_any_name=true enforce_hostnames=false max_ttl="720h" generate_lease=true


#proxy

cat <<EOT | vault policy write kubernetes/policy/proxy -
path "kubernetes/issue/proxy" {
  policy = "write"
}
path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT
vault write auth/token/roles/proxy orphan=true allowed_policies="kubernetes/policy/proxy" period="24h"
vault write kubernetes/roles/proxy organization="system:node-proxier" allow_any_name=true enforce_hostnames=false max_ttl="720h" generate_lease=true

#cluster-admin

cat <<EOT | vault policy write kubernetes/policy/cluster-admin -
path "kubernetes/issue/cluster-admin" {
  policy = "write"
}
path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT
vault write auth/token/roles/cluster-admin orphan=true allowed_policies="kubernetes/policy/cluster-admin" period="24h"
vault write kubernetes/roles/cluster-admin organization="system:masters" allow_any_name=true enforce_hostnames=false max_ttl="8760h" generate_lease=true

#addon-manager

cat <<EOT | vault policy write kubernetes/policy/addon-manager -
path "kubernetes/issue/addon-manager" {
  policy = "write"
}
path "secret/kubernetes/service-account-key" {
  policy = "read"
}
EOT
vault write auth/token/roles/addon-manager orphan=true allowed_policies="kubernetes/policy/addon-manager" period="24h"
vault write kubernetes/roles/addon-manager organization="system:masters" allow_any_name=true enforce_hostnames=false max_ttl="720h" generate_lease=true

#service account secret key

vault read -field key secret/kubernetes/service-account-key > $PKI_DIR/service-account-key.pem
if [[ ! -s $PKI_DIR/service-account-key.pem ]]; then
  openssl genrsa 4096 | vault kv put secret/kubernetes/service-account-key key=-
  vault read -field key secret/kubernetes/service-account-key > $PKI_DIR/service-account-key.pem
fi

#enable AWS integration

if [ "$VPC_ID" ]; then
vault auth enable aws
cat <<EOT | vault policy write aws/policy/knode -
path "secret/aws/*" {
  policy = "write"
}
path "auth/aws/login" {
  policy = "write"
}
path "auth/token/lookup-self" {
  policy = "read"
}
path "/auth/token/*" {
  capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
}
EOT
vault write auth/aws/role/knode auth_type=ec2 bound_vpc_id="$VPC_ID" policies="aws/policy/knode,kubernetes/policy/kubelet,kubernetes/policy/proxy"
vault write auth/aws/config/client sts_endpoint="https://sts.$REGION.amazonaws.com"
fi


#tokens for consul template to generate certs of built-in services

vault token create -role="apiserver" > $PKI_DIR/KMASTER_TOKEN
vault token create -role="kube-controller-manager" > $PKI_DIR/KUBE_CONTROLLER_MANAGER_TOKEN
vault token create -role="kube-scheduler" > $PKI_DIR/KUBE_SCHEDULER_TOKEN
vault token create -role="kubelet" > $PKI_DIR/KUBELET_TOKEN
vault token create -role="proxy" > $PKI_DIR/PROXY_TOKEN
vault token create -role="addon-manager" > $PKI_DIR/ADDON_MANAGER_TOKEN

#cluster-admin kubeconfig

ROLE=cluster-admin

DATA=$(vault write --format=json kubernetes/issue/$ROLE common_name=$ROLE ttl="8760h")
echo $DATA|jq -r .data.issuing_ca > $PKI_DIR/$ROLE-ca.pem
echo $DATA|jq -r .data.certificate > $PKI_DIR/$ROLE-cert.pem
echo $DATA|jq -r .data.private_key > $PKI_DIR/$ROLE-key.pem

kubectl config set-cluster kubernetes \
    --certificate-authority=$PKI_DIR/$ROLE-ca.pem \
    --embed-certs=true \
    --server=$KUBERNETES_MASTER \
    --kubeconfig=$VAULT_DATA_DIR/$ROLE-kubeconfig.yml
kubectl config set-credentials $ROLE \
    --client-certificate=$PKI_DIR/$ROLE-cert.pem \
    --embed-certs=true \
    --client-key=$PKI_DIR/$ROLE-key.pem \
    --kubeconfig=$VAULT_DATA_DIR/$ROLE-kubeconfig.yml
kubectl config set-context default \
    --cluster=kubernetes \
    --user=$ROLE \
    --kubeconfig=$VAULT_DATA_DIR/$ROLE-kubeconfig.yml
kubectl config use-context default --kubeconfig=$VAULT_DATA_DIR/$ROLE-kubeconfig.yml
rm $PKI_DIR/$ROLE*.pem

# kubernetes auth method

cat <<EOT | vault policy write kubernetes/policy/vault-agent -
path "secret/vault-agent/*" {
    capabilities = ["read", "list"]
}
# For K/V v2 secrets engine
path "secret/data/vault-agent/*" {
    capabilities = ["read", "list"]
}
EOT
vault write auth/token/roles/vault-agent orphan=true allowed_policies="kubernetes/policy/vault-agent" period="24h"
vault write kubernetes/roles/vault-agent allow_any_name=true enforce_hostnames=false max_ttl="8760h" generate_lease=true

vault auth enable kubernetes
vault write auth/kubernetes/config \
    kubernetes_host=$KUBERNETES_MASTER \
    kubernetes_ca_cert=@$PKI_DIR/kubernetes-ca.pem \
    disable_iss_validation=true

vault write auth/kubernetes/role/vault-agent \
        bound_service_account_names='*' \
        bound_service_account_namespaces='*' \
        policies=kubernetes/policy/vault-agent \
        ttl=1440h
