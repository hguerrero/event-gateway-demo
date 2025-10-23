# Kong Event Gateway (KEG) - Kubernetes Deployment

A complete Kubernetes deployment for the Kong Event Gateway (KEG) proxying an Apache Kafka cluster with mock data provided by Kafka Connect.

## Overview

This repository provides Kubernetes-ready manifests for deploying Kong Event Gateway as a secure, multi-tenant Kafka gateway. KEG acts as a proxy layer between Kafka clients and Kafka clusters, enabling virtualization, tenant aware routing, TLS termination, authentication mediation, and advanced topic management capabilities.

The Kafka cluster is managed by the Strimzi Operator and is configured with KRaft mode.
Data is produced in real-time by Kafka Connect. A Kafka UI viewable in your browser (`http://localhost:80`) is automatically deployed and configured to connect to the Kafka cluster. External access is mediated by the Kong Ingress Controller. Configuration for the kafkactl CLI tool is provided for easy access to the Kafka cluster, but you can also use an external client of your choice.

All external access (including accessing the Kafka UI) requires utilizing the deployed loadbalancer service. Cloud deployments may require additional configuration to route traffic to the loadbalancer service. Local deployments will depend on the type of k8s cluster but tools like `minikube` can utilize `sudo minikube tunnel -p <your-profile-name>` to expose the loadbalancer service.

## 📋 Prerequisites

- Kubernetes cluster (1.24+)
- kubectl configured
- helm installed
- [Gateway API experimental](https://gateway-api.sigs.k8s.io/) installed in cluster
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
  ```

## 🚀 Quick Start

### 1. Create Namespaces

```bash
kubectl create namespace kafka && kubectl create namespace keg && kubectl create namespace kafka-ui && kubectl create namespace kic
```

### 2. Setup TLS Certificates

```bash
# Install cert-manager in the clusterif not already installed
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml

# Create CA cert and CA issuer
kubectl apply -f certificates/CA/self-signed-ca-cert.yaml -n keg
kubectl apply -f certificates/CA/ca-issuer-bootstrap.yaml -n keg

# Deploy cluster issuer
kubectl apply -f certificates/cluster-issuer.yaml -n keg
# Deploy certificate resources
kubectl apply -f certificates/keg-certificates.yaml -n keg
```

### 3. Deploy Kafka Cluster

```bash
# Install strimzi in the kafka namespace. The version must be locked to match the Kafka cluster version.
curl -L https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.47.0/strimzi-cluster-operator-0.47.0.yaml \
  | sed 's/namespace: .*/namespace: kafka/' \
  | kubectl apply -f - -n kafka

# Deploy Kafka resources
kubectl apply -f kafka/ -n kafka
```

### 4. Deploy KEG

```bash
# Create Konnect secret (replace with your values)
kubectl create secret generic konnect-env-secret \
  --from-literal=KONNECT_REGION=<your-region> \
  --from-literal=KONNECT_DOMAIN=konghq.com \
  --from-literal=KONNECT_GATEWAY_CLUSTER_ID=<control-plane-id> \
  --from-literal=KONNECT_CLIENT_CERT=<full-client-certificate> \
  --from-literal=KONNECT_CLIENT_KEY=<full-client-key> \
  -n keg

# Deploy KEG components
kubectl apply -f keg/ -n keg
```

### 5. Configure Kong Ingress Controller (KIC) with TLSRoute support

```bash
# Create Konnect client certificate secret (replace with your values)
kubectl create secret tls konnect-client-tls -n kic --cert=./tls.crt --key=./tls.key

# Add Kong Ingress Controller repository
helm repo add kong https://charts.konghq.com
helm repo update

# Install KIC with TLSRoute support. KIC must be installed with the `--set controller.ingressController.env.feature_gates="FillIDs=true,GatewayAlpha=true"` flag to enable TLSRoute support. If installing with Helm, the provided values.yaml file already sets the `feature_gates` environment variable for you.
helm install kong kong/ingress -n kic \
  --values ./kic/values.yaml

# Deploy Gateway API resources
kubectl apply -f kic/ -n kic
```

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kafka Client  │───▶│   Kong Gateway   │───▶│  KNEP Proxy     │
│   (team-a)      │    │  (TLS Route)     │    │  (SNI Router)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                                                         ▼
                                               ┌─────────────────┐
                                               │  Kafka Cluster  │
                                               │   (Strimzi)     │
                                               └─────────────────┘
```

### Traffic Flow

1. **Client Connection**: External Kafka clients connect to the loadbalancer service `bootstrap.<virtual-cluster-name>.127-0-0-1.sslip.io:9094`
2. **Kong Ingress Controller**: Routes TLS traffic based on SNI to KEG service
3. **KEG**: Terminates TLS, applies topic prefixing, forwards to Kafka
4. **Kafka Cluster**: Processes requests with prefixed topics (`<virtual-cluster-prefix>-<topic-name>`)
