# INJI, one-click deployment on Azure

![infra](assets/inji_architecture_.png)

## Introduction

## Deployment Approach

Deployment uses the following tools:

- **Terraform for Azure** - Infrastructure deployment
- **Helm chart** - Application/Microservices deployment


The entire Terraform deployment is divided into 2 stages -

- **Pre-Config** stage
    - Create the required infra for deployment
- **Setup** Stage
    - Deploy the Core services

### Helm Chart Details
#### INJI
Currently, the below release version of the Helm charts will be deployed. The version can be updated in the [.env](.env) file if needed.

| Chart                      | Chart Version | Docker Image                 | Docker Version |
|----------------------------|---------------|------------------------------|----------------|
| mosip/inji-certify         | 0.9.0         | mosipid/inji-certify         | 0.9.0          |
| mosip/mimoto               | 0.13.1        | tejashjl/mimoto              | develop        |
| mosip/injiweb              | 0.9.0         | mosipdev/inji-web            | develop        |
| mosip/injiverify           | 0.9.0         | mosipqa/inji-verify          | latest         |

#### eSignet
Currently, the below release version of the Helm charts will be deployed. The version can be updated in the [deployments/.esignet.env](deployments/.esignet.env) file if needed.

| Chart                      | Chart Version | Docker Image                 | Docker Version       |
|----------------------------|---------------|------------------------------|----------------------|
| mosip/softhsm              | 12.0.1        | mosipid/softhsm              | v2                   |
| mosip/artifactory          | 12.0.1        | tejashjl/artifactory-server  | develop              |
| mosip/keycloak             | 7.1.18        | mosipid/mosip-keycloak       | 16.1.1-debian-10-r85 |
| mosip/postgres-init        | 12.0.1        | mosipid/postgres-init        | 1.2.0.1              |
| mosip/esignet              | 1.4.1         | mosipid/esignet              | 1.4.0                |
| mosip/oidc-ui              | 1.4.1         | mosipid/oidc-ui              | 1.4.0                |
| mosip/keycloak-init        | 12.0.1        | mosipid/keycloak-init        | 1.2.0.1              |
| mosip/mock-identity-system | 0.9.3         | mosipid/mock-identity-system | 0.9.3                |


#### RC
Currently, the below release version of the Helm charts will be deployed. The version can be updated in the [deployments/.registry.env](deployments/.registry.env) file if needed.

| Service                   | Docker Version |
|---------------------------|----------------|
| registry                  | v1.0.0         |
| credential_schema_service | v2.0.0-rc3     |
| credentials_service       | v2.0.0-rc3     |
| keycloak_service          | v1.0.0         |
| identity_service_version  | v2.0.0-rc3     |


### Pre-requisites

- #### [Install the azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)

- #### [Install terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

- #### Azure account and subscription id

### Workspace - Folder structure

- **(***Root Folder***)**
    - **assets**
        - images
        - architetcure diagrams
        - ...(more)
    - **deployments -** Store config files required for deployment
        - **configs**
            - Store config files required for deployment
        - **scripts**
            - Shell scripts required to deploy services
    - **terraform-scripts**
        - Deployment files for end to end Infrastructure deployment
    


## Step-by-Step guide for INJI deployment

### Infrastructure Deployment

#### Terraform State management
Pre-requisites:
- Subscription ID

```bash
cd terraform-scripts/storage-state
terraform init
terraform plan  -var="subscription_id=***" 
terraform apply  -var="subscription_id=***" 
```

#### Terraform infra
Pre-requisites:
- Subscription ID
- SSH public key

```bash
cd terraform-scripts/infra
terraform init
terraform plan -var="subscription_id=***" -var="bastion_admin_password=admin@123" -var="ssh_public_key=ssh***"
terraform apply -var="subscription_id=***" -var="bastion_admin_password=admin@123" -var="ssh_public_key=ssh***"
```

Output
```bash
Apply complete! Resources: 1 added, 1 changed, 0 destroyed.

Outputs:

lb_ip = "20.44.100.211"
resource_group_name = "inji-rg-dev"
```

After infra deployment, you would need to point 4 domains/sub-domain to the above LoadBalancer IP
Domains:
1. FR Domain - Ex: (demofr.domain.com)
2. eSignet Domain - Ex: (demoesignet.domain.com)
3. Inji Domain - Ex: (demoinji.domain.com)
4. Inji Verify Domain - Ex: (demoverify.domain.com)

### INJI service deployment

#### Connect to bastion host
Update the private ssh key path and subscription id in below command
```bash
az network bastion ssh --name "bastion-dev" --resource-group "inji-rg-dev" --target-resource-id "/subscriptions/**subscription_id**/resourceGroups/inji-rg-dev/providers/Microsoft.Compute/virtualMachines/bastion-vm-dev" --auth-type "ssh-key" --ssh-key "~/.ssh/id_ed25519" --username adminuser
```
Install az cli and login
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

az login
```

Run the below script to deploy INJI services
```bash
curl -O https://raw.githubusercontent.com/tejash-jl/azure-devops/refs/heads/main/inji_deploy.sh 
bash inji_deploy.sh 
```

#### Connect to PSQL
Get PSQL admin password
```bash
echo $(az keyvault secret show --vault-name psql-kv-dev --name psql-password | jq -r '.value')
```
Connect to psql
```bash
sudo apt-get install postgresql-client
psql --host inji-psql-dev.postgres.database.azure.com -d postgres -U psqladmin
```


### DEMO
The postman collection (along with env config) has been provided in `postman_collections` directory.

Open postman and import both the collection and environment collections

- Select the `inji-env` environment from the dropdown
- Update `REGISTRY_HOST` env with _FR_DOMAIN_ value
- Update `ESIGNET_HOST` env with _ESIGNET_DOMAIN_ value
- Update `INJI_HOST` env with _DOMAIN_ value
- Update `client_secret` env with the keycloak secret value, by running the below cmd,
```bash
  echo Secret: $(kubectl get secrets keycloak-client-secrets -n esignet -o jsonpath="{.data.mosip_pms_client_secret}" | base64 --decode)
```

**1. Function Registry Setup**

You can follow the below steps to initialize RC, you can trigger the apis in the given order in `RC` directory of the postman collection.
- Now generate a DID(POST /did/generate) and create a credential schema(POST /credential-schema)
  - take note of $.schema[0].author and $.schema[0].id from the create credential schema request
  - host the output of the JSON to the GitHub pages repo created earlier
- Next, to modify the properties of the Esignet and Certify services located in the deployments/esignet-local.properties and deployments/certify-local.properties files respectively.
  trigger the deploy script to update the properties of esignet/certify services
```bash
curl -O https://raw.githubusercontent.com/tejash-jl/azure-devops/refs/heads/main/update_did.sh
bash update_did.sh
```

**2. eSignet Setup**

- You can now create a OIDC Client, goto `eSignet/OIDC Client Mgmt` section in postman collection and trigger all the APIs to create a OIDC client
- Copy `privateKey_jwk` env value from postman environment 
- Run the below command to mount the private key as p12 file to mimoto service
```bash
curl -O https://raw.githubusercontent.com/tejash-jl/azure-devops/refs/heads/main/upload_p12.sh
bash upload_p12.sh
```
- Next you can run the apis in `eSignet/KBA` and verify if you are able to access the credential

**3. Inji Web Demo**

Next you can test the inji web by following the below steps:
- Launch the Inji Web application in your web browser (Use _DOMAIN_)
- In the Home page, from the section, List of Issuers section, click on issuers' tile to land in Credential Types selection page.
- Click on a Credential Type tile and authenticate in the eSignet page by providing the required details.
- Provide the patient details that was created in the postman collection, For ex: Patient ID: p-123, Patient Name: ram, Patient DoB: 14-09-2024
- Credential is downloaded in the background and PDF will be generated and stored in the Downloads folder of the system.
- Upon successful PDF generation, user can view the PDF of the downloaded VC

**4. Mobile Wallet Demo**

Next you can test the inji wallet by following the below steps:
- Launch the Inji Wallet application in your simulator/phone
- After the app setup you can follow the same steps provided above to download the VC for the user.

**5. Inji Verify Demo**

Next you can test the inji verify by following the below steps:
- Launch the Inji Verify application in your mobile browser (Use _VERIFY_DOMAIN_)
- In the Home page, select `Scan the QR Code` tab and scan the qr code present in the PDF file that was downloaded in the previous step.
- If QR code is valid, the details of the VC and status will be shown


### Destruction

```bash
terraform destroy
```

or

```bash
az group delete -y -n inji-rg-dev
az group delete -y -n inji_node_rg_dev
```