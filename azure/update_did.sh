#!/bin/bash

update_did(){
  cd ~/azure-devops/


  echo -n "$1" | xargs -I '{}' sed -i -E 's@mosip.esignet.vciplugin.sunbird-rc.credential-type.VaccinationCredential.static-value-map.issuerId=.*@mosip.esignet.vciplugin.sunbird-rc.credential-type.VaccinationCredential.static-value-map.issuerId={}@' esignet-local.properties
  echo -n "$1" | xargs -I '{}' sed -i -E 's@mosip.certify.vciplugin.sunbird-rc.credential-type.VaccinationCredential.static-value-map.issuerId=.*@mosip.certify.vciplugin.sunbird-rc.credential-type.VaccinationCredential.static-value-map.issuerId={}@' certify-local.properties

  echo -n "$2" | xargs -I '{}' sed -i -E 's@mosip.esignet.vciplugin.sunbird-rc.credential-type.VaccinationCredential.cred-schema-id=.*@mosip.esignet.vciplugin.sunbird-rc.credential-type.VaccinationCredential.cred-schema-id={}@' esignet-local.properties
  echo -n "$2" | xargs -I '{}' sed -i -E 's@mosip.certify.vciplugin.sunbird-rc.credential-type.VaccinationCredential.cred-schema-id=.*@mosip.certify.vciplugin.sunbird-rc.credential-type.VaccinationCredential.cred-schema-id={}@' certify-local.properties
  kubectl create configmap certify-local-properties -n esignet --from-file=certify-local.properties -o yaml --dry-run=client | kubectl apply -f - -n esignet
  kubectl create configmap esignet-local-properties -n esignet --from-file=esignet-local.properties -o yaml --dry-run=client | kubectl apply -f - -n esignet
  kubectl rollout restart deploy inji-certify -n esignet
  kubectl rollout restart deploy esignet -n esignet
}

get_input() {
    local prompt="$1"
    read -p "$prompt : " input_value
    echo "$input_value"
}

did=$(get_input "Enter the DID id generated")
schema=$(get_input "Enter the schema id generated")

update_did $did $schema