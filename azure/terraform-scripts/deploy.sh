#!/bin/bash

install_istio() {
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update
    #manually create the namespace
    kubectl create namespace istio-system
    #install the base (CRDs)
    helm install istio-base istio/base -n istio-system
    #install IstioD (the control plane)
    helm install istiod istio/istiod -n istio-system -- wait

    echo "Installing Istio Ingress Gateway..."
    helm install istio-ingress istio/gateway -n istio-system --set service.type=LoadBalancer

    # Label the default namespace to enable Istio sidecar injection
    echo "Labeling default namespace for Istio sidecar injection..."
    kubectl label namespace dev istio-injection=enabled --overwrite

    echo "Verifying Istio installation:"
    kubectl get pods -n istio-system
}

# Deploy self-hosted PostgreSQL
deploy_postgresql() {
    echo "Deploying self-hosted PostgreSQL..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    kubectl create namespace postgres --dry-run=client -o yaml | kubectl apply -f -
    helm install postgresql-release bitnami/postgresql --namespace dev -f dev-values.yaml
}

# Deploy self-hosted Redis
deploy_redis() {
    echo "Deploying self-hosted Redis..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    kubectl create namespace redis --dry-run=client -o yaml | kubectl apply -f -
    helm install redis-release bitnami/redis --namespace redis -f dev-values.yaml
}

# Deploy self-hosted Kafka
deploy_kafka() {
    echo "Deploying self-hosted Kafka..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
    helm install kafka-release bitnami/kafka --namespace kafka -f dev-values.yaml
}

# Execute deployments
install_istio
deploy_postgresql
deploy_redis
deploy_kafka