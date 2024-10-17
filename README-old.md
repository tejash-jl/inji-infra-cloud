# Learn Terraform - Provision AKS Cluster

This repo is a companion repo to the [Provision an AKS Cluster tutorial](https://developer.hashicorp.com/terraform/tutorials/kubernetes/aks), containing Terraform configuration files to provision an AKS cluster on Azure.


Bastion host connect
```bash
az network bastion ssh --name "bastion-dev" --resource-group "inji-rg-dev" --target-resource-id "/subscriptions/8648ad76-d99c-4938-9706-0afb8a13b73c/resourceGroups/inji-rg-dev/providers/Microsoft.Compute/virtualMachines/bastion-vm-dev" --auth-type "ssh-key" --ssh-key "~/.ssh/id_ed25519" --username adminuser
```
Cluster connect
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

az login

az account set --subscription 8648ad76-d99c-4938-9706-0afb8a13b73c

sudo bash

az aks install-cli

az aks get-credentials --resource-group inji-rg-dev --name inji-aks-dev --overwrite-existing

kubectl get nodes

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version
```
install ingress
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml
```

install vault
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com

echo 'server:
  affinity: ""
  ha:
    enabled: false
    raft:
      enabled: true
      setNodeId: true
      config: |
        cluster_name = "vault-integrated-storage"
        storage "raft" {
           path    = "/vault/data/"
        }
        
        listener "tcp" {
           address = "[::]:8200"
           cluster_address = "[::]:8201"
           tls_disable = "true"
        }
        service_registration "kubernetes" {}' > vault-raft.yaml

helm install vault hashicorp/vault --values=vault-raft.yaml -n vault --create-namespace

sudo apt-get install jq -y
kubectl -n vault wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 

cluster_keys=""
cluster_keys=$(kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json)
sleep 10
VAULT_UNSEAL_KEY=$(echo "$cluster_keys" | jq -r ".unseal_keys_b64[]")
kubectl exec -n vault vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"

CLUSTER_ROOT_TOKEN=$(echo "$cluster_keys" | jq -r ".root_token")
kubectl exec -n vault vault-0 -- vault login "$CLUSTER_ROOT_TOKEN"
kubectl exec -n vault vault-0 -- vault operator raft list-peers
kubectl get pods -n vault

echo -e "\nSet vault enable kubernetes\n"

kubectl exec -n vault vault-0 -n vault -- vault auth enable kubernetes
echo -e "\nvault set secret path\n"

kubectl exec -n vault vault-0 -n vault -- vault secrets enable -path=kv kv-v2

echo -e "\nVault setup completed successfully!!!"

kubectl create secret generic vault --from-literal=token="$CLUSTER_ROOT_TOKEN"
```
install cert manager
```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --version v1.15.1 -n cert-manager --create-namespace --set crds.enabled=true
```

install issuer
```bash
echo 'apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: jl.tejash@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx' > cert-issuer.yaml
kubectl create ns registry
kubectl apply -f cert-issuer.yaml -n registry
```
install rc
```bash
git clone https://github.com/tejash-jl/sunbird-rc-devops.git
cd sunbird-rc-devops/deploy-as-code/helm/v2/registryAndCredentialling/helm_charts/
echo 'registry_version=v1.0.0
credential_schema_service_version=v2.0.0-rc3
credentials_service_version=v2.0.0-rc3
identity_service_version=v2.0.0-rc3
certificate_api_version=v1.0.0
certificate_signer_version=v1.0.0
claim_ms_version=v2.0.0
context_proxy_service_version=v1.0.0
encryption_service_version=v2.0.0
id_gen_service_version=v2.0.0
keycloak_service_version=v1.0.0
notification_ms_version=v2.0.0
public_key_service_version=v1.0.0' > .env

rm -rf charts/registry/schemas/*
wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/schemas/registry/Hospital.json
wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/schemas/registry/Vaccination.json
cp Hospital.json charts/registry/schemas
cp Vaccination.json charts/registry/schemas

sudo apt-get install jq uuid-runtime -y
db_pass=H@Sh1CoR3!
keycloak_admin_password=$(openssl rand -hex 12)
db_host=inji-psql-dev.postgres.database.azure.com
echo -n "$db_pass" | base64 -w 0 | xargs -I '{}' sed -i -E 's@DB_PASSWORD.*@DB_PASSWORD: {}@' values.yaml
echo -n "$keycloak_admin_password" | base64 -w 0 | xargs -I '{}' sed -i -E 's@KEYCLOAK_ADMIN_PASSWORD:.*@KEYCLOAK_ADMIN_PASSWORD: {}@' values.yaml
kubectl get secret vault -o jsonpath='{.data}' | jq -r '.token' | xargs -I '{}' sed -i -E 's@VAULT_SECRET_TOKEN:.*@VAULT_SECRET_TOKEN: {}@' values.yaml
echo -n "postgres://psqladmin:$db_pass@$db_host:5432/credentials" | base64 -w 0 | xargs -I '{}' sed -i -E 's@CREDENTIALS_DB_URL:.*@CREDENTIALS_DB_URL: {}@' values.yaml
echo -n "postgres://psqladmin:$db_pass@$db_host:5432/credential-schema" | base64 -w 0 | xargs -I '{}' sed -i -E 's@CREDENTIAL_SCHEMA_DB_URL:.*@CREDENTIAL_SCHEMA_DB_URL: {}@' values.yaml
echo -n "postgres://psqladmin:$db_pass@$db_host:5432/identity" | base64 -w 0 | xargs -I '{}' sed -i -E 's@IDENTITY_DB_URL:.*@IDENTITY_DB_URL: {}@' values.yaml
echo -n "$db_host" | xargs -I '{}' sed -i -E 's@host: "10.9.0.7".*@host: {}@' values.yaml
echo -n "$db_host" | xargs -I '{}' sed -i -E 's@db:5432@{}:5432@' values.yaml
sed -i -E 's@http://vault:@http://vault.vault:@' values.yaml
admin_secret=$(uuidgen)
echo -n "$admin_secret" | base64 -w 0 | xargs -I '{}' sed -i -E 's@KEYCLOAK_ADMIN_CLIENT_SECRET:.*@KEYCLOAK_ADMIN_CLIENT_SECRET: {}@' values.yaml
kubectl create secret generic keycloak --from-literal=password="$keycloak_admin_password" --from-literal=secret="$admin_secret"
echo -n "testfr.dpgongcp.com" | xargs -I '{}' sed -i -E 's@sunbird_sso_url: .*@sunbird_sso_url: https://{}/auth@' charts/config/templates/configmap.yaml
echo -n "testfr.dpgongcp.com" | xargs -I '{}' sed -i -E 's@OAUTH2_RESOURCES_0_URI: .*@OAUTH2_RESOURCES_0_URI: https://{}/auth/realms/sunbird-rc@' charts/config/templates/configmap.yaml

export $(grep -v '^#' .env | xargs -d '\n')


helm install -n registry registry . --create-namespace \
  --set global.host=testfr.dpgongcp.com \
  --set global.registry.search_provider=dev.sunbirdrc.registry.service.NativeSearchService \
  --set global.registry.keycloak_user_set_password=true --set global.database.user=psqladmin \
  --set-json registry.ingress.annotations='{"kubernetes.io/ingress.class": "nginx", "nginx.ingress.kubernetes.io/rewrite-target": "/$2", "cert-manager.io/issuer": "letsencrypt", "nginx.ingress.kubernetes.io/force-ssl-redirect": "true"}' \
  --set-json registry.ingress.tls='[{"hosts": ["testfr.dpgongcp.com"], "secretName": "registry-tls"}]' \
  --set certificate-api.image.tag=$certificate_api_version \
  --set claim-ms.image.tag=$claim_ms_version \
  --set context-proxy-service.image.tag=$context_proxy_service_version \
  --set credential-schema-service.image.tag=$credential_schema_service_version \
  --set certificate-signer.image.tag=$certificate_signer_version \
  --set credentials-service.image.tag=$credentials_service_version \
  --set encryption-service.image.tag=$encryption_service_version \
  --set id-gen-service.image.tag=$id_gen_service_version \
  --set identity-service.image.tag=$identity_service_version \
  --set keycloak-service.image.tag=$keycloak_service_version \
  --set notification-ms.image.tag=$notification_ms_version \
  --set public-key-service.image.tag=$public_key_service_version \
  --set registry.image.tag=$registry_version

kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n registry

wget https://raw.githubusercontent.com/tejash-jl/gcp-devops/refs/heads/main/deployments/configs/keycloak-init-job.yaml

echo -n "https://testfr.dpgongcp.com" | xargs -I '{}' sed -i -E 's@DOMAIN_VALUE@{}@' keycloak-init-job.yaml

kubectl apply -f keycloak-init-job.yaml -n registry

kubectl rollout restart deploy registry-keycloak-service -n registry
kubectl rollout restart deploy registry -n registry
kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n registry

kubectl delete deploy -n registry registry-certificate-api registry-certificate-signer registry-claim-ms registry-context-proxy-service registry-id-gen-service registry-encryption-service registry-notification-ms registry-public-key-service
alias k=kubectl

kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n registry
WEB_DID=https://tejash-jl.github.io/DID-Resolve
kubectl get cm -n registry registry-config -o yaml | sed -e 's|WEB_DID_BASE_URL: https://example.com/identifier|WEB_DID_BASE_URL: '"$WEB_DID"'|' | kubectl apply -f - -n registry

kubectl rollout restart deploy registry-identity-service -n registry
kubectl rollout restart deploy registry -n registry
```

eSignet
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n redis --create-namespace --set auth.enabled=false --set architecture=standalone

wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/esignet-local.properties
wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/.esignet.env

mv -rf esignet-local.properties esignet.properties
mv -rf .esignet.env .env
kubectl create ns esignet
echo 'apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: jl.tejash@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx' > cert-issuer.yaml
kubectl apply -f cert-issuer.yaml -n esignet

helm repo add strimzi https://strimzi.io/charts/

helm install strimzi strimzi/strimzi-kafka-operator -n kafka --create-namespace

wget https://raw.githubusercontent.com/tejash-jl/eSignet-Stack/refs/heads/main/deployments/configs/kafka.yml
kubectl apply -f kafka.yml -n kafka

sudo apt-get update
sudo apt-get install jq wget -y
wget https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64.tar.gz -O - | tar xz && sudo mv yq_linux_amd64 /usr/bin/yq
export $(grep -v '^#' .env | xargs -d '\n')
helm repo add mosip https://mosip.github.io/mosip-helm


echo 'resources:
  limits: {}
  #   cpu: 250m
  #   memory: 1Gi
  requests:
    cpu: 100m
    memory: 20Mi' > softhsm.yaml

wget https://raw.githubusercontent.com/tejash-jl/eSignet-Stack/refs/heads/main/deployments/configs/keycloak.yaml
sed -i -E 's@registry@psqladmin@' keycloak.yaml
domain=testesignet.dpgongcp.com

sqlIP=inji-psql-dev.postgres.database.azure.com
sqlPass=H@Sh1CoR3!     

helm install softhsm mosip/softhsm -n esignet --create-namespace --set image.repository="$softhsm_docker_image" --set image.tag="$softhsm_docker_version" -f softhsm.yaml --version "$softhsm_helm_version" --wait
helm install artifactory mosip/artifactory -n esignet --create-namespace --set image.repository=$artifactory_docker_image --set image.tag=$artifactory_docker_version --version $artifactory_helm_version --wait
helm install keycloak mosip/keycloak -n esignet --create-namespace --version $keycloak_helm_version -f keycloak.yaml --set ingress.hostname=$domain --set externalDatabase.host=$sqlIP --set externalDatabase.password=$sqlPass --set image.repository=$keycloak_docker_image --set image.tag=$keycloak_docker_version --wait
kubectl create secret -n esignet generic postgres --from-literal=password="$sqlPass" 

wget https://raw.githubusercontent.com/tejash-jl/eSignet-Stack/refs/heads/main/deployments/configs/db_init.yaml
sed -i -E 's@user: postgres@user: psqladmin@' db_init.yaml
sed -i -E 's@https://github.com/tejash-jl/eSignet-Stack.git@https://github.com/tejash-jl/azure-devops.git@' db_init.yaml
helm -n esignet install postgres-init mosip/postgres-init -f db_init.yaml --version $postgres_init_helm_version --set databases.mosip_esignet.host=$sqlIP --set image.repository=$postgres_init_docker_image --set image.tag=$postgres_init_docker_version --wait

sudo apt-get install jq gettext -y
LOCAL_ESIGNET_PROPERTIES=esignet.properties
UPDATED_ESIGNET_PROPERTIES=esignet-local.properties
export AUTHENTICATOR_SERVICE=MockAuthenticationService
export ESIGNET_HOST=testesignet.dpgongcp.com
export API_INTERNAL=testesignet.dpgongcp.com
export KEYCLOAK_URL=testesignet.dpgongcp.com
export SOFTHSM_PIN=$(kubectl get secrets softhsm -n esignet -o jsonpath={.data.security-pin} | base64 --decode)
export KAFKA_URL=kafka-cluster-kafka-bootstrap.kafka:9092
export DB_HOST=inji-psql-dev.postgres.database.azure.com
export DB_PORT=5432
export DB_USERNAME=psqladmin
export DB_PASSWORD=H@Sh1CoR3!
export REDIS_HOST=redis-master.redis.svc.cluster.local
export API_PUBLIC_HOST=testesignet.dpgongcp.com
export MISP_KEY=''

envsubst < $LOCAL_ESIGNET_PROPERTIES  > $UPDATED_ESIGNET_PROPERTIES

kubectl create configmap esignet-local-properties -n esignet  --from-file=$UPDATED_ESIGNET_PROPERTIES


echo "esignet config map created"      

wget https://raw.githubusercontent.com/tejash-jl/eSignet-Stack/refs/heads/main/deployments/configs/esignet-values.yaml
helm -n esignet template esignet mosip/esignet --version $esignet_helm_version -f esignet-values.yaml --set image.repository=$esignet_docker_image --set image.tag=$esignet_docker_version > deploy.yaml
yq  e -i 'select(di == 3).spec.template.spec.volumes += [{"name":"esignet-properties","configMap":{"name":"esignet-local-properties"}}]' deploy.yaml
yq e -i 'select(di == 3).spec.template.spec.containers[0] += {"volumeMounts":[{"mountPath":"/home/mosip/esignet-local.properties","name":"esignet-properties","subPath":"esignet-local.properties"}]}' deploy.yaml
kubectl apply -f deploy.yaml -n esignet

wget https://raw.githubusercontent.com/tejash-jl/eSignet-Stack/refs/heads/main/deployments/configs/ui-values.yaml
helm -n esignet install oidc-ui mosip/oidc-ui -f ui-values.yaml --version $oidcui_helm_version --set image.repository=$oidcui_docker_image --set image.tag=$oidcui_docker_version --wait

wget https://raw.githubusercontent.com/tejash-jl/eSignet-Stack/refs/heads/main/deployments/configs/ingress.yaml
cat ingress.yaml | sed 's/DOMAIN/testesignet.dpgongcp.com/'  | kubectl apply -n esignet -f -
kubectl create configmap keycloak-host --from-literal=keycloak-internal-service-url=http://keycloak.esignet.svc.cluster.local:80/auth/ -n esignet &&
helm -n esignet install keycloak-init mosip/keycloak-init --set frontend=https://testesignet.dpgongcp.com/auth --version $keycloak_init_helm_version --set image.repository=$keycloak_init_docker_image --set image.tag=$keycloak_init_docker_version



export FR_DOMAIN=testfr.dpgongcp.com
envsubst < $LOCAL_ESIGNET_PROPERTIES  > $UPDATED_ESIGNET_PROPERTIES

kubectl create configmap esignet-local-properties -n esignet --from-file=$UPDATED_ESIGNET_PROPERTIES -o yaml --dry-run=client | kubectl apply -f - -n esignet

kubectl rollout restart deploy esignet -n esignet

kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n esignet

echo "esignet config map created"

```

install inji certify
```bash
echo 'postgres_init_helm_version=0.0.1-develop
postgres_init_docker_image=mosipid/postgres-init
postgres_init_docker_version=1.2.0.1

certify_helm_version=0.9.0
certify_docker_image=mosipid/inji-certify
certify_docker_version=0.9.0


mimoto_helm_version=0.13.1
mimoto_docker_image=tejashjl/mimoto
mimoto_docker_version=develop


injiweb_helm_version=0.9.0
injiweb_docker_image=mosipdev/inji-web
injiweb_docker_version=develop


injiverify_helm_version=0.9.0
injiverify_docker_image=mosipqa/inji-verify
injiverify_docker_version=latest' > .env
export $(grep -v '^#' .env | xargs -d '\n')
helm repo add mosip https://mosip.github.io/mosip-helm
sqlIP=inji-psql-dev.postgres.database.azure.com
sqlPass=H@Sh1CoR3!     

kubectl -n esignet delete secret db-common-secrets
rm db_init.yaml
wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/db_init.yaml
sed -i -E 's@user: postgres@user: psqladmin@' db_init.yaml
sed -i -E 's@https://github.com/tejash-jl/inji-stack.git@https://github.com/tejash-jl/azure-devops.git@' db_init.yaml

helm -n esignet install postgres-init-certify mosip/postgres-init -f db_init.yaml --version $postgres_init_helm_version --set databases.mosip_certify.host=$sqlIP --set image.repository=$postgres_init_docker_image --set image.tag=$postgres_init_docker_version --wait

wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/certify-local.properties
mv certify-local.properties certify.properties

LOCAL_CERTIFY_PROPERTIES=certify.properties
UPDATED_CERTIFY_PROPERTIES=certify-local.properties
export AUTHENTICATOR_SERVICE=MockAuthenticationService
export ESIGNET_HOST=testesignet.dpgongcp.com
export API_INTERNAL=testesignet.dpgongcp.com
export KEYCLOAK_URL=testesignet.dpgongcp.com
export FR_DOMAIN=testfr.dpgongcp.com
export INJI_DOMAIN=testinji.dpgongcp.com
export SOFTHSM_PIN=$(kubectl get secrets softhsm -n esignet -o jsonpath={.data.security-pin} | base64 --decode)
export KAFKA_URL=kafka-cluster-kafka-bootstrap.kafka:9092
export DB_HOST=inji-psql-dev.postgres.database.azure.com
export DB_PORT=5432
export DB_USERNAME=psqladmin
export DB_PASSWORD=H@Sh1CoR3!
export REDIS_HOST=redis-master.redis.svc.cluster.local
export MISP_KEY=''

envsubst < $LOCAL_CERTIFY_PROPERTIES  > $UPDATED_CERTIFY_PROPERTIES

kubectl create configmap certify-local-properties -n esignet --from-file=$UPDATED_CERTIFY_PROPERTIES -o yaml --dry-run=client | kubectl apply -f - -n esignet

echo "certify config map created"

wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/certify-values.yaml
helm -n esignet template inji-certify mosip/inji-certify --version $certify_helm_version -f certify-values.yaml --set image.repository=$certify_docker_image --set image.tag=$certify_docker_version > deploy.yaml
yq  e -i 'select(di == 3).spec.template.spec.volumes += [{"name":"certify-properties","configMap":{"name":"certify-local-properties"}}]' deploy.yaml
yq e -i 'select(di == 3).spec.template.spec.containers[0] += {"volumeMounts":[{"mountPath":"/home/mosip/certify-local.properties","name":"certify-properties","subPath":"certify-local.properties"}]}' deploy.yaml
kubectl apply -f deploy.yaml -n esignet

wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/inji-ingress.yaml
wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/inji-residentmobileapp-ingress.yaml
cat inji-ingress.yaml | sed 's/DOMAIN/testinji.dpgongcp.com/'  | kubectl apply -n esignet -f -
cat inji-residentmobileapp-ingress.yaml | sed 's/DOMAIN/testinji.dpgongcp.com/'  | kubectl apply -n esignet -f -

```
inji mimoto
```bash
wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/mimoto-default.properties
wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/mimoto-issuers-config.json
wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/templates/credential-template.html

mv mimoto-default.properties mimoto.properties
mv mimoto-issuers-config.json mimoto-config.json


MIMOTO_PROPERTIES=mimoto.properties
UPDATED_MIMOTO_PROPERTIES=mimoto-default.properties

MIMOTO_ISSUERS_CONFIG=mimoto-config.json
UPDATED_MIMOTO_ISSUERS_CONFIG=mimoto-issuers-config.json

MIMOTO_CERTIFICATE_TEMPLATE=credential.html
UPDATED_MIMOTO_CERTIFICATE_TEMPLATE=credential-template.html

export ESIGNET_HOST=testesignet.dpgongcp.com
export INJI_HOST=testinji.dpgongcp.com

envsubst < $MIMOTO_PROPERTIES  > $UPDATED_MIMOTO_PROPERTIES
envsubst < $MIMOTO_ISSUERS_CONFIG  > $UPDATED_MIMOTO_ISSUERS_CONFIG


kubectl create configmap mimoto-local-properties -n esignet --from-file=$UPDATED_MIMOTO_PROPERTIES --from-file=$UPDATED_MIMOTO_ISSUERS_CONFIG --from-file=$UPDATED_MIMOTO_CERTIFICATE_TEMPLATE -o yaml --dry-run=client | kubectl apply -f - -n esignet

wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/mimoto-values.yaml

helm -n esignet template mimoto mosip/mimoto --version $mimoto_helm_version -f mimoto-values.yaml --set image.repository=$mimoto_docker_image --set image.tag=$mimoto_docker_version > deploy.yaml
yq e -i 'select(di == 3).spec.template.spec.volumes += [{"name":"mimoto-properties","configMap":{"name":"mimoto-local-properties"}}]' deploy.yaml
yq e -i 'select(di == 3).spec.template.spec.containers[0].volumeMounts += [{"mountPath":"/home/mosip/mimoto-default.properties","name":"mimoto-properties","subPath":"mimoto-default.properties"},{"mountPath":"/home/mosip/mimoto-issuers-config.json","name":"mimoto-properties","subPath":"mimoto-issuers-config.json"}]' deploy.yaml
yq e -i 'select(di == 3).spec.template.spec.containers[0] += {"ports":[{"name":"spring-service","containerPort":8099}]}' deploy.yaml

kubectl apply -f deploy.yaml -n esignet

wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/file-store.yml
kubectl apply -f file-store.yml -n esignet


wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/inji-web-values.yaml
helm -n esignet install injiweb mosip/injiweb -f inji-web-values.yaml --version $injiweb_helm_version --set image.repository=$injiweb_docker_image --set image.tag=$injiweb_docker_version  --set inji_web.inji_web_service_host=mimoto.esignet --set esignet_redirect_url=https://testinji.dpgongcp.com

wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/inji-verify-ingress.yaml
cat inji-verify-ingress.yaml | sed 's/DOMAIN/testverify.dpgongcp.com/'  | kubectl apply -n esignet -f -

wget https://raw.githubusercontent.com/tejash-jl/inji-infra-cloud/refs/heads/master/gcp/deployments/configs/inji-verify-values.yaml
helm -n esignet install injiverify mosip/injiverify -f inji-verify-values.yaml --version $injiverify_helm_version --set image.repository=$injiverify_docker_image --set image.tag=$injiverify_docker_version --set esignet_redirect_url=https://testinji.dpgongcp.com

```

certify config update
```bash
LOCAL_CERTIFY_PROPERTIES=certify.properties
UPDATED_CERTIFY_PROPERTIES=certify-local.properties
export AUTHENTICATOR_SERVICE=MockAuthenticationService
export ESIGNET_HOST=testesignet.dpgongcp.com
export API_INTERNAL=testesignet.dpgongcp.com
export KEYCLOAK_URL=testesignet.dpgongcp.com
export FR_DOMAIN=testfr.dpgongcp.com
export INJI_DOMAIN=testinji.dpgongcp.com
export SOFTHSM_PIN=$(kubectl get secrets softhsm -n esignet -o jsonpath={.data.security-pin} | base64 --decode)
export KAFKA_URL=kafka-cluster-kafka-bootstrap.kafka:9092
export DB_HOST=inji-psql-dev.postgres.database.azure.com
export DB_PORT=5432
export DB_USERNAME=psqladmin
export DB_PASSWORD=H@Sh1CoR3!
export REDIS_HOST=redis-master.redis.svc.cluster.local
export MISP_KEY=''

envsubst < $LOCAL_CERTIFY_PROPERTIES  > $UPDATED_CERTIFY_PROPERTIES

kubectl create configmap certify-local-properties -n esignet --from-file=$UPDATED_CERTIFY_PROPERTIES -o yaml --dry-run=client | kubectl apply -f - -n esignet

echo "certify config map created"
kubectl rollout restart deploy inji-certify -n esignet

```

mimoto p12
```bash
vi key.jwk
sudo apt install npm -y
npm install -g cli-jwk-to-pem
jwk=$(cat key.jwk)
jwk-to-pem --jwk $jwk > key.pem
openssl req -new -sha256 -key key.pem -out csr.csr -subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=example.com"

openssl req -x509 -sha256 -days 365 -key key.pem -in csr.csr -out certificate.pem

export pass=$(cat mimoto-default.properties | grep "mosip.oidc.p12.password" | sed  -e 's/mosip.oidc.p12.password=//g')

openssl pkcs12 -export -out oidckeystore.p12 -inkey key.pem -in certificate.pem --name esignet-sunbird-partner -passout env:pass
kubectl create secret generic mimotooidc -n esignet --from-file=oidckeystore.p12
kubectl rollout restart deploy mimoto -n esignet
```

psql connect
```bash
sudo apt-get install postgresql-client
psql --host inji-psql-dev.postgres.database.azure.com -d postgres -U psqladmin
```