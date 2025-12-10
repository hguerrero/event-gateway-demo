# Kong Event Gateway (KEG) - Kubernetes Deployment

A complete Kubernetes deployment for the Kong Event Gateway (KEG) proxying an Apache Kafka cluster with mock data provided by Kafka Connect.

## Overview

This repository provides Kubernetes-ready manifests for deploying Kong Event Gateway as a secure, multi-tenant Kafka gateway. KEG acts as a proxy layer between Kafka clients and Kafka clusters, enabling virtualization, tenant aware routing, TLS termination, authentication mediation, and advanced topic management capabilities.

The Kafka cluster is managed by the Strimzi Operator and is configured with KRaft mode.
Data is produced in real-time by Kafka Connect. A Kafka UI viewable in your browser (`http://localhost:80`) is automatically deployed and configured to connect to the Kafka cluster. External access is mediated by the Kong Ingress Controller. Configuration for the kafkactl CLI tool is provided for easy access to the Kafka cluster, but you can also use an external client of your choice.

Observability is provided through OpenTelemetry, with traces exported to Jaeger and metrics to Prometheus. Both Jaeger and Prometheus UIs are accessible via HTTPRoutes through the Kong Ingress Controller.

All external access (including accessing the Kafka UI) requires utilizing the deployed loadbalancer service. Cloud deployments may require additional configuration to route traffic to the loadbalancer service. Local deployments will depend on the type of k8s cluster but tools like `minikube` can utilize `sudo minikube tunnel -p <your-profile-name>` to expose the loadbalancer service.

## 📋 Prerequisites

- Kubernetes cluster (1.24+)
- kubectl configured
- helm installed
- [Gateway API experimental](https://gateway-api.sigs.k8s.io/) installed in cluster
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
  ```

## 💻 Resource Requirements

This deployment includes multiple components that require adequate cluster resources. Below are the resource requirements for each component:

### Cluster Requirements

- **Total CPU**: ~5.5 cores
- **Total Memory**: ~10GB
- **Storage**: Ephemeral storage for Kafka brokers (persistent storage recommended for production)

### Component Resource Breakdown

| Component                         | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
| --------------------------------- | ----------- | --------- | -------------- | ------------ | -------- |
| **Kafka Brokers**                 | 750m        | 1.2 cores | 2.3GB          | 3GB          | 3        |
| **KEG Gateway**                   | 500m        | 750m      | 512MB          | 1GB          | 1        |
| **Kafka Connect (Operations)**    | 250m        | 400m      | 768MB          | 1GB          | 1        |
| **Kafka Connect (Analytics)**     | 250m        | 400m      | 768MB          | 1GB          | 1        |
| **Kafka UI**                      | 200m        | 300m      | 768MB          | 1GB          | 1        |
| **OpenTelemetry Collector**       | 200m        | 500m      | 256MB          | 512MB        | 1        |
| **Jaeger**                        | 200m        | 500m      | 512MB          | 1GB          | 1        |
| **Prometheus**                    | 200m        | 500m      | 512MB          | 1GB          | 1        |
| **KIC (Kong Ingress Controller)** | ~200m       | ~500m     | ~256MB         | ~512MB       | 1        |
| **Strimzi Operators**             | ~100m       | ~200m     | ~256MB         | ~512MB       | 1        |

> **Note**: These are minimum requirements for a functional deployment. Production environments should allocate additional resources for performance, monitoring, and high availability.

### 1. Create Namespaces

```bash
kubectl create namespace kafka && kubectl create namespace keg && kubectl create namespace kafka-ui && kubectl create namespace kic && kubectl create namespace observability
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

### 8. Deploy Observability Stack

```bash
# Deploy observability components (Jaeger, Prometheus, OpenTelemetry Collector)
# Note: Deploy Jaeger first as the OTEL collector references it
# All observability components are deployed in the observability namespace
kubectl apply -f observability/jaeger.yaml
kubectl apply -f observability/prometheus.yaml
kubectl apply -f observability/otel-collector.yaml

# Deploy HTTPRoutes for accessing observability UIs
kubectl apply -f observability/jaeger-httproute.yaml
kubectl apply -f observability/prometheus-httproute.yaml
```

The observability stack provides:
- **Jaeger**: Distributed tracing UI accessible at `http://<loadbalancer-ip>/jaeger`
- **Prometheus**: Metrics querying UI accessible at `http://<loadbalancer-ip>/prometheus`
- **OpenTelemetry Collector**: Receives traces and metrics from Event Gateway and forwards them to Jaeger and Prometheus

The Event Gateway is configured with OpenTelemetry tracing enabled and exports:
- **Traces**: Sent via OTLP/gRPC to the OpenTelemetry Collector, which forwards to Jaeger
- **Metrics**: Exposed on the health listener (port 8080) and scraped by the OpenTelemetry Collector, which forwards to Prometheus

Key metrics available include:
- `kong_keg_kafka_connections_active`: Active Kafka connections
- `kong_keg_kafka_backend_roundtrip_duration_seconds`: Backend roundtrip duration
- `kong_keg_kafka_request_received_count_total`: Total API requests received

The `OTEL_SERVICE_NAME` environment variable (set to `keg`) identifies the service name in traces and metrics, making it easier to filter and identify Event Gateway data in observability tools.

### 9. Ensure loadbalancer service is accessible

If running locally, ensure the loadbalancer service is accessible. Cloud deployments may require additional configuration to route traffic to the loadbalancer service. Local deployments will depend on the type of k8s cluster but tools like `minikube` can utilize `sudo minikube tunnel -p <your-profile-name>` to expose the loadbalancer service.

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kafka Client  │───▶│   Kong Gateway   │───▶│  KEG Proxy     │
│   (TLS required)│    │  (TLS Route)     │    │  (SNI Router)   │
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

## Internal Notes

- **Kafka 4.0 Upgrade**: Updating to Kafka 4.0 will require updating to a matching Strimzi version
- **Connector Creation Delays**: Need to verify if delays are between creating the connect clusters and deploying the connectors when taking a fully automated approach to deployment
- **Virtual Cluster Limitations**: When adding new virtual clusters, Kubernetes services are not automatically generated. See keg/keg-vc-broker-dns.yaml for current manual approach. This will need to be automated in the future with the Kong Operator.
  - External Kafka clients require updates to tlsroutes managed by KIC.
- **Virtual Cluster Name Changes**: Changing virtual cluster names impacts DNS and certificates - use with caution. See certificates/cluster-certificates.yaml for current manual approach. This will need to be automated in the future with the Kong Operator.
