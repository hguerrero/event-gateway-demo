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
kubectl apply -f certificates/ca-bootstrap.yaml -n cert-manager

# Deploy certificate resources for cluster
kubectl apply -f certificates/cluster-certificates.yaml
```

### 3. Deploy Kafka Cluster

```bash
# Install strimzi in the kafka namespace. The version must be locked to match the Kafka cluster version.
curl -L https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.47.0/strimzi-cluster-operator-0.47.0.yaml \
  | sed 's/namespace: .*/namespace: kafka/' \
  | kubectl apply -f - -n kafka

# Deploy core Kafka cluster resources
kubectl apply -f kafka/kafka-cluster/ -n kafka
```

### 4. Deploy KEG

```bash
# Create Konnect secret specific to your KEG control plane. These values can be found in the Kong Konnect console when deploying a KEG dataplane
kubectl create secret generic konnect-env-secret \
  --from-literal=KONNECT_REGION=<your-region> \
  --from-literal=KONNECT_DOMAIN=konghq.com \
  --from-literal=KONNECT_GATEWAY_CLUSTER_ID=<control-plane-id> \
  --from-literal=KONNECT_CLIENT_CERT=<full-client-certificate> \
  --from-literal=KONNECT_CLIENT_KEY=<full-client-key> \
  -n keg

# Deploy KEG components and setup services and namespaces for the virtual clusters
kubectl apply -f keg/
```

### 5. Configure Kong Ingress Controller (KIC) with TLSRoute support

```bash
# Create Konnect client certificate and config secrets specific to your KIC control plane. These values can be found in the Kong Konnect console when deploying a KIC dataplane.

# Download the client certificate and key from the Kong Konnect console and save them to the current directory
kubectl create secret tls konnect-client-tls -n kic --cert=<client-certificate>.crt --key=<client-key>.key
# Create Konnect config secret specific to KIC
kubectl create secret generic konnect-config -n kic \
  --from-literal=CONTROL_PLANE_ID=<control-plane-id> \
  --from-literal=CLUSTER_TELEMETRY_ENDPOINT=<cluster-telemetry-endpoint> \
  --from-literal=CLUSTER_TELEMETRY_SERVER_NAME=<cluster-telemetry-server-name> \
  --from-literal=API_HOSTNAME=<api-hostname>

# Add Kong Ingress Controller repository
helm repo add kong https://charts.konghq.com
helm repo update

# Install KIC with TLSRoute support. KIC must be installed with the `--set controller.ingressController.env.feature_gates="FillIDs=true,GatewayAlpha=true"` flag to enable TLSRoute support. If installing with Helm, the provided values.yaml file already sets the `feature_gates` environment variable for you.
helm install kong kong/ingress -n kic \
  --values ./kic/values.yaml \
  --set controller.ingressController.konnect.controlPlaneID="$(kubectl get secret konnect-config -n kic -o jsonpath='{.data.CONTROL_PLANE_ID}' | base64 -d)" \
  --set controller.ingressController.konnect.apiHostname="$(kubectl get secret konnect-config -n kic -o jsonpath='{.data.API_HOSTNAME}' | base64 -d)"

# Deploy Gateway API resources
kubectl apply -f kic/kic-gateway.yaml
```

### 6. Deploy Kafka Connect

```bash
# Deploy Kafka Connect clusters
kubectl apply -f kafka/kafka-connect/kafka-connect-operations.yaml -f kafka/kafka-connect/kafka-connect-analytics.yaml

# Deploy Kafka Connect connectors
kubectl apply -f kafka/kafka-connect/connectors/
```

### 7. Deploy Kafka UI

```bash
# Deploy Kafka UI
kubectl apply -f kafka-ui/
```

### 8. Ensure loadbalancer service is accessible

If running locally, ensure the loadbalancer service is accessible. Cloud deployments may require additional configuration to route traffic to the loadbalancer service. Local deployments will depend on the type of k8s cluster but tools like `minikube` can utilize `sudo minikube tunnel -p <your-profile-name>` to expose the loadbalancer service.

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
