#!/bin/bash

upload_p12(){
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  nvm install 20
  node -v
  npm -v
  openssl version

  npm install -g cli-jwk-to-pem
  jwk=$1
  jwk-to-pem --jwk $jwk > key.pem

  openssl req -new -sha256 -key key.pem -out csr.csr -subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=example.com"

  openssl req -x509 -sha256 -days 365 -key key.pem -in csr.csr -out certificate.pem

  export pass=$(cat ~/azure-devops/azure/mimoto-default.properties | grep "mosip.oidc.p12.password" | sed  -e 's/mosip.oidc.p12.password=//g')
  openssl pkcs12 -export -out oidckeystore.p12 -inkey key.pem -in certificate.pem --name esignet-sunbird-partner -passout env:pass

  kubectl create secret generic mimotooidc -n esignet --from-file=oidckeystore.p12
  kubectl rollout restart deploy mimoto -n esignet
  kubectl rollout restart deploy file-store -n esignet
}

get_input() {
    local prompt="$1"
    read -p "$prompt : " input_value
    echo "$input_value"
}

pkey=$(get_input "Enter the private key")

upload_p12 $pkey