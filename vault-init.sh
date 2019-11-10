#!/bin/bash

# Allow mlock to avoid swapping Vault memory to disk
setcap cap_ipc_lock=+ep $(readlink -f $(which vault))

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
vault write kubernetes/roles/proxy allow_any_name=true enforce_hostnames=false max_ttl="720h" generate_lease=true


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
EOT
vault write auth/aws/role/knode auth_type=ec2 bound_vpc_id="$VPC_ID" policies="aws/policy/knode,kubernetes/policy/kubelet,kubernetes/policy/proxy"
fi


#tokens

vault token create -role="apiserver" > $PKI_DIR/KMASTER_TOKEN
vault token create -role="kubelet" > $PKI_DIR/KUBELET_TOKEN

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


#cluster-admin kubeconfig

export ROLE=cluster-admin
export USER=cluster-admin
export KUBERNETES_MASTER="${KUBERNETES_MASTER:-https://$HOSTNAME:$SECURE_PORT}"

vault token create -role="cluster-admin" > $PKI_DIR/CLUSTER_ADMIN_TOKEN
#grep "token " $PKI_DIR/CLUSTER_ADMIN_TOKEN | awk '{print $2}' | xargs vault login
rm $PKI_DIR/CLUSTER_ADMIN_TOKEN

DATA=$(vault write --format=json kubernetes/issue/$ROLE common_name=$ROLE ttl="8760h")
echo $DATA|jq -r .data.issuing_ca > $PKI_DIR/$ROLE-ca.pem
echo $DATA|jq -r .data.certificate > $PKI_DIR/$ROLE-cert.pem
echo $DATA|jq -r .data.private_key > $PKI_DIR/$ROLE-key.pem

kubectl config set-cluster kubernetes \
    --certificate-authority=$PKI_DIR/$ROLE-ca.pem \
    --embed-certs=true \
    --server=$KUBERNETES_MASTER \
    --kubeconfig=$PKI_DIR/$ROLE-kubeconfig.yml
kubectl config set-credentials $USER \
    --client-certificate=$PKI_DIR/$ROLE-cert.pem \
    --embed-certs=true \
    --client-key=$PKI_DIR/$ROLE-key.pem \
    --kubeconfig=$PKI_DIR/$ROLE-kubeconfig.yml
kubectl config set-context default \
    --cluster=kubernetes \
    --user=$USER \
    --kubeconfig=$PKI_DIR/$ROLE-kubeconfig.yml
kubectl config use-context default --kubeconfig=$PKI_DIR/$ROLE-kubeconfig.yml
rm $PKI_DIR/$ROLE*.pem

