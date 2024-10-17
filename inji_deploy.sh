#!/bin/bash

get_input() {
    local prompt="$1"
    read -p "$prompt : " input_value
    echo "$input_value"
}

install_kubectl() {
  sudo az aks install-cli

  az aks get-credentials --resource-group inji-rg-dev --name inji-aks-dev --overwrite-existing

  kubectl get nodes
}

install_helm() {

  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3

  chmod 700 get_helm.sh

  ./get_helm.sh

  helm version
}

install_pre_req(){
  sudo apt-get install jq uuid-runtime wget gettext -y
  wget https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64.tar.gz -O - | tar xz && sudo mv yq_linux_amd64 /usr/bin/yq
  install_kubectl
  install_helm
}

install_ingress() {
  wget  -O deploy.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml
  az network public-ip show -g inji_node_rg_dev -n glb-ip-dev | jq -r ".ipAddress" | xargs -I '{}' sed -i -E 's@LoadBalancer@LoadBalancer\n  loadBalancerIP: {}@' deploy.yaml
  kubectl apply -f deploy.yaml
}

clone_repo() {
  git clone https://github.com/tejash-jl/azure-devops.git
  cd azure-devops
}

install_vault() {
  helm repo add hashicorp https://helm.releases.hashicorp.com

  helm install vault hashicorp/vault --values=deployments/configs/vault-raft.yaml -n vault --create-namespace

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
}

install_cert_manager() {
  helm repo add jetstack https://charts.jetstack.io
  helm install cert-manager jetstack/cert-manager --version v1.15.1 -n cert-manager --create-namespace --set crds.enabled=true
}

install_issuer() {
  kubectl create ns $2
  local email_id="$1"
  cat deployments/configs/cert-issuer.yaml | sed "s/EMAIL/${email_id}/g" | kubectl apply -n $2 -f -
}

install_rc() {
  git clone https://github.com/tejash-jl/sunbird-rc-devops.git
  cp deployments/configs/.registry.env sunbird-rc-devops/deploy-as-code/helm/v2/registryAndCredentialling/helm_charts/.env
  rm -rf sunbird-rc-devops/deploy-as-code/helm/v2/registryAndCredentialling/helm_charts/charts/registry/schemas/*
  cp deployments/schemas/Hospital.json sunbird-rc-devops/deploy-as-code/helm/v2/registryAndCredentialling/helm_charts/charts/registry/schemas
  cp deployments/schemas/Hospital.json sunbird-rc-devops/deploy-as-code/helm/v2/registryAndCredentialling/helm_charts/charts/registry/schemas

  cd sunbird-rc-devops/deploy-as-code/helm/v2/registryAndCredentialling/helm_charts/

  db_pass=$(az keyvault secret show --vault-name psql-kv-dev --name psql-password | jq -r '.value')
  keycloak_admin_password=$(openssl rand -hex 12)
  db_host=inji-psql-dev.postgres.database.azure.com
  admin_secret=$(uuidgen)
  local fr_host="$1"
  local web_did="$2"

  echo -n "$db_pass" | base64 -w 0 | xargs -I '{}' sed -i -E 's@DB_PASSWORD.*@DB_PASSWORD: {}@' values.yaml
  echo -n "$keycloak_admin_password" | base64 -w 0 | xargs -I '{}' sed -i -E 's@KEYCLOAK_ADMIN_PASSWORD:.*@KEYCLOAK_ADMIN_PASSWORD: {}@' values.yaml
  kubectl get secret vault -o jsonpath='{.data}' | jq -r '.token' | xargs -I '{}' sed -i -E 's@VAULT_SECRET_TOKEN:.*@VAULT_SECRET_TOKEN: {}@' values.yaml
  echo -n "postgres://psqladmin:$db_pass@$db_host:5432/credentials" | base64 -w 0 | xargs -I '{}' sed -i -E 's@CREDENTIALS_DB_URL:.*@CREDENTIALS_DB_URL: {}@' values.yaml
  echo -n "postgres://psqladmin:$db_pass@$db_host:5432/credential-schema" | base64 -w 0 | xargs -I '{}' sed -i -E 's@CREDENTIAL_SCHEMA_DB_URL:.*@CREDENTIAL_SCHEMA_DB_URL: {}@' values.yaml
  echo -n "postgres://psqladmin:$db_pass@$db_host:5432/identity" | base64 -w 0 | xargs -I '{}' sed -i -E 's@IDENTITY_DB_URL:.*@IDENTITY_DB_URL: {}@' values.yaml
  echo -n "$db_host" | xargs -I '{}' sed -i -E 's@host: "10.9.0.7".*@host: {}@' values.yaml
  echo -n "$db_host" | xargs -I '{}' sed -i -E 's@db:5432@{}:5432@' values.yaml
  sed -i -E 's@http://vault:@http://vault.vault:@' values.yaml
  echo -n "$admin_secret" | base64 -w 0 | xargs -I '{}' sed -i -E 's@KEYCLOAK_ADMIN_CLIENT_SECRET:.*@KEYCLOAK_ADMIN_CLIENT_SECRET: {}@' values.yaml
  kubectl create secret generic keycloak --from-literal=password="$keycloak_admin_password" --from-literal=secret="$admin_secret"
  echo -n "$fr_host" | xargs -I '{}' sed -i -E 's@sunbird_sso_url: .*@sunbird_sso_url: https://{}/auth@' charts/config/templates/configmap.yaml
  echo -n "$fr_host" | xargs -I '{}' sed -i -E 's@OAUTH2_RESOURCES_0_URI: .*@OAUTH2_RESOURCES_0_URI: https://{}/auth/realms/sunbird-rc@' charts/config/templates/configmap.yaml

  export $(grep -v '^#' .env | xargs -d '\n')


  helm install -n registry registry . --create-namespace \
    --set global.host=$fr_host \
    --set global.registry.search_provider=dev.sunbirdrc.registry.service.NativeSearchService \
    --set global.registry.keycloak_user_set_password=true --set global.database.user=psqladmin \
    --set-json registry.ingress.annotations='{"kubernetes.io/ingress.class": "nginx", "nginx.ingress.kubernetes.io/rewrite-target": "/$2", "cert-manager.io/issuer": "letsencrypt", "nginx.ingress.kubernetes.io/force-ssl-redirect": "true"}' \
    --set-json registry.ingress.tls='[{"hosts": ["'$fr_host'"], "secretName": "registry-tls"}]' \
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
  kubectl delete deploy -n registry registry-certificate-api registry-certificate-signer registry-claim-ms registry-context-proxy-service registry-id-gen-service registry-encryption-service registry-notification-ms registry-public-key-service

  kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n registry


  echo -n "https://$fr_host" | xargs -I '{}' sed -i -E 's@DOMAIN_VALUE@{}@' ~/azure-devops/deployments/configs/keycloak-init-job.yaml

  kubectl apply -f ~/azure-devops/deployments/configs/keycloak-init-job.yaml -n registry
  kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n registry
  kubectl get cm -n registry registry-config -o yaml | sed -e 's|WEB_DID_BASE_URL: https://example.com/identifier|WEB_DID_BASE_URL: '"$WEB_DID"'|' | kubectl apply -f - -n registry
  kubectl rollout restart deploy registry-keycloak-service -n registry
  kubectl rollout restart deploy registry-identity-service -n registry
  kubectl rollout restart deploy registry -n registry
  kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n registry
}

install_esignet() {
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo add strimzi https://strimzi.io/charts/
  helm repo add mosip https://mosip.github.io/mosip-helm

  helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n redis --create-namespace --set auth.enabled=false --set architecture=standalone
  helm install strimzi strimzi/strimzi-kafka-operator -n kafka --create-namespace

  kubectl apply -f deployments/configs/kafka.yml -n kafka

  export $(grep -v '^#' deployments/configs/.esignet.env | xargs -d '\n')

  local esignet_host="$1"
  local fr_host="$2"


  helm install softhsm mosip/softhsm -n esignet --create-namespace --set image.repository="$softhsm_docker_image" --set image.tag="$softhsm_docker_version" -f deployments/configs/softhsm.yaml --version "$softhsm_helm_version" --wait

  kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n esignet
  export SOFTHSM_PIN=$(kubectl get secrets softhsm -n esignet -o jsonpath={.data.security-pin} | base64 --decode)

  helm install artifactory mosip/artifactory -n esignet --create-namespace --set image.repository=$artifactory_docker_image --set image.tag=$artifactory_docker_version --version $artifactory_helm_version --wait

  helm install keycloak mosip/keycloak -n esignet --create-namespace --version $keycloak_helm_version -f deployments/configs/keycloak.yaml --set ingress.hostname=$domain --set externalDatabase.host=$SQLIP --set externalDatabase.password=$SQLPASS --set image.repository=$keycloak_docker_image --set image.tag=$keycloak_docker_version --wait

  kubectl create secret -n esignet generic postgres --from-literal=password="$SQLPASS"

  helm -n esignet install postgres-init mosip/postgres-init -f deployments/configs/db_init.yaml --version $postgres_init_helm_version --set databases.mosip_esignet.host=$SQLIP --set image.repository=$postgres_init_docker_image --set image.tag=$postgres_init_docker_version --wait

  LOCAL_ESIGNET_PROPERTIES=deployments/properties/esignet.properties
  UPDATED_ESIGNET_PROPERTIES=esignet-local.properties

  envsubst < $LOCAL_ESIGNET_PROPERTIES  > $UPDATED_ESIGNET_PROPERTIES

  kubectl create configmap esignet-local-properties -n esignet  --from-file=$UPDATED_ESIGNET_PROPERTIES

  helm -n esignet template esignet mosip/esignet --version $esignet_helm_version -f deployments/configs/esignet-values.yaml --set image.repository=$esignet_docker_image --set image.tag=$esignet_docker_version > deploy.yaml
  yq  e -i 'select(di == 3).spec.template.spec.volumes += [{"name":"esignet-properties","configMap":{"name":"esignet-local-properties"}}]' deploy.yaml
  yq e -i 'select(di == 3).spec.template.spec.containers[0] += {"volumeMounts":[{"mountPath":"/home/mosip/esignet-local.properties","name":"esignet-properties","subPath":"esignet-local.properties"}]}' deploy.yaml
  kubectl apply -f deploy.yaml -n esignet

  helm -n esignet install oidc-ui mosip/oidc-ui -f deployments/configs/ui-values.yaml --version $oidcui_helm_version --set image.repository=$oidcui_docker_image --set image.tag=$oidcui_docker_version --wait

  cat deployments/configs/ingress.yaml | sed 's/DOMAIN/'"$esignet_host"'/'  | kubectl apply -n esignet -f -
  kubectl create configmap keycloak-host --from-literal=keycloak-internal-service-url=http://keycloak.esignet.svc.cluster.local:80/auth/ -n esignet

  kubectl wait pod --all --for=jsonpath='{.status.phase}'=Running  -n esignet

  helm -n esignet install keycloak-init mosip/keycloak-init --set frontend=https://$esignet_host/auth --version $keycloak_init_helm_version --set image.repository=$keycloak_init_docker_image --set image.tag=$keycloak_init_docker_version


  echo "esignet config map created"
}

set_env() {
  local inji_host="$1"
  local esignet_host="$2"
  local fr_host="$3"
  export AUTHENTICATOR_SERVICE=MockAuthenticationService
  export ESIGNET_HOST=$esignet_host
  export API_INTERNAL=$esignet_host
  export KEYCLOAK_URL=$esignet_host
  export SOFTHSM_PIN=$(kubectl get secrets softhsm -n esignet -o jsonpath={.data.security-pin} | base64 --decode)
  export KAFKA_URL=kafka-cluster-kafka-bootstrap.kafka:9092
  export DB_HOST=inji-psql-dev.postgres.database.azure.com
  export DB_PORT=5432
  export DB_USERNAME=psqladmin
  export REDIS_HOST=redis-master.redis.svc.cluster.local
  export MISP_KEY=''
  export FR_DOMAIN=$fr_host
  export INJI_DOMAIN=$inji_host
  export INJI_HOST=$inji_host
  export API_PUBLIC_HOST=$esignet_host
  export SQLIP=inji-psql-dev.postgres.database.azure.com
  export SQLPASS=$(az keyvault secret show --vault-name psql-kv-dev --name psql-password | jq -r '.value')
  export DB_PASSWORD=$SQLPASS
}

install_inji_certify(){
  local inji_host="$1"
  export $(grep -v '^#' deployments/configs/.inji.env | xargs -d '\n')
  LOCAL_CERTIFY_PROPERTIES=deployments/properties/certify.properties
  UPDATED_CERTIFY_PROPERTIES=certify-local.properties
  envsubst < $LOCAL_CERTIFY_PROPERTIES  > $UPDATED_CERTIFY_PROPERTIES
  helm repo add mosip https://mosip.github.io/mosip-helm


  kubectl -n esignet delete secret db-common-secrets

  helm -n esignet install postgres-init-certify mosip/postgres-init -f deployments/configs/inji_db_init.yaml --version $postgres_init_helm_version --set databases.mosip_certify.host=$SQLIP --set image.repository=$postgres_init_docker_image --set image.tag=$postgres_init_docker_version --wait

  kubectl create configmap certify-local-properties -n esignet --from-file=$UPDATED_CERTIFY_PROPERTIES -o yaml --dry-run=client | kubectl apply -f - -n esignet

  echo "certify config map created"

  helm -n esignet template inji-certify mosip/inji-certify --version $certify_helm_version -f deployments/configs/certify-values.yaml --set image.repository=$certify_docker_image --set image.tag=$certify_docker_version > deploy.yaml
  yq  e -i 'select(di == 3).spec.template.spec.volumes += [{"name":"certify-properties","configMap":{"name":"certify-local-properties"}}]' deploy.yaml
  yq e -i 'select(di == 3).spec.template.spec.containers[0] += {"volumeMounts":[{"mountPath":"/home/mosip/certify-local.properties","name":"certify-properties","subPath":"certify-local.properties"}]}' deploy.yaml
  kubectl apply -f deploy.yaml -n esignet

  cat deployments/configs/inji-ingress.yaml | sed 's/DOMAIN/'"$inji_host"'/'  | kubectl apply -n esignet -f -
  cat deployments/configs/inji-residentmobileapp-ingress.yaml | sed 's/DOMAIN/'"$inji_host"'/'  | kubectl apply -n esignet -f -
}

install_inji_mimoto(){
  local inji_host="$1"
  local esignet_host="$2"
  local verify_host="$3"
  MIMOTO_PROPERTIES=deployments/properties/mimoto-default.properties
  UPDATED_MIMOTO_PROPERTIES=mimoto-default.properties

  MIMOTO_ISSUERS_CONFIG=deployments/properties/mimoto-issuers-config.json
  UPDATED_MIMOTO_ISSUERS_CONFIG=mimoto-issuers-config.json

  MIMOTO_CERTIFICATE_TEMPLATE=deployments/templates/credential-template.html
  UPDATED_MIMOTO_CERTIFICATE_TEMPLATE=credential-template.html

  envsubst < $MIMOTO_PROPERTIES  > $UPDATED_MIMOTO_PROPERTIES
  envsubst < $MIMOTO_ISSUERS_CONFIG  > $UPDATED_MIMOTO_ISSUERS_CONFIG


  kubectl create configmap mimoto-local-properties -n esignet --from-file=$UPDATED_MIMOTO_PROPERTIES --from-file=$UPDATED_MIMOTO_ISSUERS_CONFIG --from-file=$UPDATED_MIMOTO_CERTIFICATE_TEMPLATE -o yaml --dry-run=client | kubectl apply -f - -n esignet


  helm -n esignet template mimoto mosip/mimoto --version $mimoto_helm_version -f deployments/configs/mimoto-values.yaml --set image.repository=$mimoto_docker_image --set image.tag=$mimoto_docker_version > deploy.yaml
  yq e -i 'select(di == 3).spec.template.spec.volumes += [{"name":"mimoto-properties","configMap":{"name":"mimoto-local-properties"}}]' deploy.yaml
  yq e -i 'select(di == 3).spec.template.spec.containers[0].volumeMounts += [{"mountPath":"/home/mosip/mimoto-default.properties","name":"mimoto-properties","subPath":"mimoto-default.properties"},{"mountPath":"/home/mosip/mimoto-issuers-config.json","name":"mimoto-properties","subPath":"mimoto-issuers-config.json"}]' deploy.yaml
  yq e -i 'select(di == 3).spec.template.spec.containers[0] += {"ports":[{"name":"spring-service","containerPort":8099}]}' deploy.yaml

  kubectl apply -f deploy.yaml -n esignet

  kubectl apply -f deployments/configs/file-store.yml -n esignet

  helm -n esignet install injiweb mosip/injiweb -f deployments/configs/inji-web-values.yaml --version $injiweb_helm_version --set image.repository=$injiweb_docker_image --set image.tag=$injiweb_docker_version  --set inji_web.inji_web_service_host=mimoto.esignet --set esignet_redirect_url=https://$inji_host


  cat deployments/configs/inji-verify-ingress.yaml | sed 's/DOMAIN/'"$verify_host"'/'  | kubectl apply -n esignet -f -

  helm -n esignet install injiverify mosip/injiverify -f deployments/configs/inji-verify-values.yaml --version $injiverify_helm_version --set image.repository=$injiverify_docker_image --set image.tag=$injiverify_docker_version --set esignet_redirect_url=https://$verify_host

}

echo "Starting the deployment..."

email=$(get_input "Enter the email id for ssl certificate generation ")
rc_domain=$(get_input "Enter the domain for RC services")
esignet_domain=$(get_input "Enter the domain for eSignet services")
inji_domain=$(get_input "Enter the domain for inji services")
verify_domain=$(get_input "Enter the domain for inji verify services")
did_url=$(get_input "Enter the git repository for DID, (Ex: https://tejash-jl.github.io/DID-Resolve)")

install_pre_req

install_ingress

clone_repo
pwd
install_vault

install_cert_manager

install_issuer $email registry
install_issuer $email esignet

install_rc $rc_domain $did_url
cd ~/azure-devops/
pwd
set_env $inji_domain $esignet_domain $rc_domain
install_esignet $esignet_domain rc_domain
install_inji_certify $inji_domain
install_inji_mimoto $inji_domain $esignet_domain $verify_domain

echo "Depployment completed."