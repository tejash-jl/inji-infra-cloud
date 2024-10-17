sudo bash

az aks install-cli

exit

az aks get-credentials --resource-group inji-rg-dev --name inji-aks-dev --overwrite-existing

kubectl get nodes