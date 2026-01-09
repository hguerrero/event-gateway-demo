# Kong Event Gateway (KEG) - Kubernetes Deployment

A complete Kubernetes deployment for the Kong Event Gateway (KEG) proxying an Apache Kafka cluster with mock data provided by Kafka Connect.

## Overview

This repository provides Kubernetes-ready manifests for deploying Kong Event Gateway as a secure, multi-tenant Kafka gateway. KEG acts as a proxy layer between Kafka clients and Kafka clusters, enabling virtualization, tenant aware routing, TLS termination, authentication mediation, and advanced topic management capabilities.

The Kafka cluster is managed by the Strimzi Operator and is configured with KRaft mode.
Data is produced in real-time by Kafka Connect. A Kafka UI viewable in your browser (http://localhost:80) is automatically deployed and configured to connect to the Kafka cluster. External access is mediated by the Kong Ingress Controller. Configuration for the kafkactl CLI tool is provided for easy access to the Kafka cluster, but you can also use an external client of your choice.

Observability is provided through OpenTelemetry, with traces exported to Jaeger and metrics to Prometheus. Both Jaeger (http://localhost/jaeger) and Prometheus (http://localhost/prometheus) UIs are accessible via HTTPRoutes through the Kong Ingress Controller.

All external access (including accessing the Kafka UI) requires utilizing the deployed loadbalancer service. Cloud deployments may require additional configuration to route traffic to the loadbalancer service. Local deployments will depend on the type of k8s cluster but tools like `minikube` can utilize `sudo minikube tunnel -p <your-profile-name>` to expose the loadbalancer service.

## 🔗 Links to access the demo environment

Once deployed, the following services are accessible via the loadbalancer:

| Service        | URL                                                                    | Description                                                         |
| -------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------- |
| **Kafka UI**   | `http://<loadbalancer-ip>` or `http://localhost:80`                    | Web interface for managing and monitoring Kafka clusters and topics |
| **Jaeger**     | `http://<loadbalancer-ip>/jaeger` or `http://localhost/jaeger`         | Distributed tracing UI for viewing request traces                   |
| **Prometheus** | `http://<loadbalancer-ip>/prometheus` or `http://localhost/prometheus` | Metrics querying and visualization UI                               |

> **Note**: Replace `<loadbalancer-ip>` with your actual loadbalancer IP address. For local deployments using `localhost`, ensure the loadbalancer service is properly exposed (e.g., using `minikube tunnel`).

## 📋 Prerequisites

- Kubernetes cluster (1.24+)
- kubectl configured
- helm installed
- Terraform installed (required for Kong Event Gateway configuration in Konnect)
- [Gateway API experimental](https://gateway-api.sigs.k8s.io/) v1.3.0 installed in cluster
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
  ```
- cert-manager (will be installed in step 2)
- Strimzi Kafka Operator (will be installed in step 3)
- Kong Konnect account with API token (required for Terraform setup)
- For minikube users: minikube installed and configured

> **⚠️ Warning for Minikube Users**: If leave your minikube cluster running while your computer sleeps, over time your system clock may get out of sync and you may experience issues with certificate validation and service connectivity. A simple restart of minikube (`minikube stop && minikube start`) typically resolves these issues.

## 🖥️ Minikube-Specific Setup (Optional)

If you're using minikube for local development, consider the following additional setup:

### Enable Metrics Server

The metrics server addon is useful for resource monitoring and autoscaling features:

```bash
minikube addons enable metrics-server
```

### Resource Considerations

Ensure your minikube cluster has sufficient resources allocated. The deployment requires approximately:

- **CPU**: ~3.2 cores (requests) / ~5.8 cores (limits)
- **Memory**: ~8GB (requests) / ~12GB (limits)

You can configure these when starting minikube:

```bash
minikube start --cpus=6 --memory=12g
```

Or adjust an existing cluster:

```bash
minikube stop
minikube start --cpus=6 --memory=12g
```

### LoadBalancer Access

For minikube, use `minikube tunnel` to expose LoadBalancer services:

```bash
# Run in a separate terminal (requires sudo)
sudo minikube tunnel -p <your-profile-name>
```

This allows external access to services via the LoadBalancer IP.

## 💻 Resource Requirements

This deployment includes multiple components that require adequate cluster resources. Below are the resource requirements for each component:

### Cluster Requirements

- **Total CPU**: ~3.2 cores (requests) / ~5.8 cores (limits)
- **Total Memory**: ~8GB (requests) / ~12GB (limits)
- **Storage**: Ephemeral storage for Kafka brokers (persistent storage recommended for production)

### Component Resource Breakdown

| Component                      | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
| ------------------------------ | ----------- | --------- | -------------- | ------------ | -------- |
| **Kafka Brokers**              | 750m        | 1.2 cores | 2.3GB          | 3GB          | 3        |
| **KEG Gateway**                | 500m        | 750m      | 512MB          | 1GB          | 1        |
| **Kafka Connect (Operations)** | 250m        | 400m      | 768MB          | 1GB          | 1        |
| **Kafka Connect (Analytics)**  | 250m        | 400m      | 768MB          | 1GB          | 1        |
| **Kafka UI**                   | 200m        | 300m      | 768MB          | 1GB          | 1        |
| **OpenTelemetry Collector**    | 200m        | 500m      | 384Mi          | 512Mi        | 1        |
| **Jaeger**                     | 200m        | 500m      | 1Gi            | 2Gi          | 1        |
| **Prometheus**                 | 200m        | 500m      | 512MB          | 1GB          | 1        |
| **KIC Controller**             | 100m        | 250m      | 256Mi          | 512Mi        | 1        |
| **KIC Gateway**                | 500m        | 1000m     | 512Mi          | 1.5Gi        | 1        |
| **Strimzi Operators**          | 100m        | 400m      | 256Mi          | 512Mi        | 1        |

> **Note**: These are minimum requirements for a functional deployment. Production environments should allocate additional resources for performance, monitoring, and high availability.

### 1. Create Namespaces

```bash
kubectl create namespace kafka && kubectl create namespace keg && kubectl create namespace kafka-ui && kubectl create namespace kic && kubectl create namespace observability
```

### 2. Setup TLS Certificates

1. Install cert-manager in the cluster if not already installed

   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml
   ```

2. Create CA cert and CA issuer

   ```bash
   kubectl apply -f certificates/ca-bootstrap.yaml -n cert-manager
   ```

3. Deploy certificate resources for cluster
   ```bash
   kubectl apply -f certificates/cluster-certificates.yaml
   ```

### 3. Deploy Kafka Cluster

1. Install strimzi in the kafka namespace. The version must be locked to match the Kafka cluster version.

   ```bash
   curl -L https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.47.0/strimzi-cluster-operator-0.47.0.yaml \
     | sed 's/namespace: .*/namespace: kafka/' \
     | kubectl apply -f - -n kafka
   ```

2. Deploy core Kafka cluster resources
   ```bash
   kubectl apply -f kafka/kafka-cluster/ -n kafka
   ```

### 4. Configure Kong Event Gateway with Terraform

This step configures the Kong Event Gateway in Konnect, including the backend cluster, virtual clusters, listeners, and policies. This should be completed before deploying KEG (step 5).

**Prerequisites:**

- Terraform installed ([installation instructions](https://developer.hashicorp.com/terraform/downloads))
- Kong Konnect personal access token (create one in the Konnect console)

**Setup Terraform configuration:**

1. Copy the example variables file

   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   ```

2. Set the required variables

   ```yaml
   # - konnect_token: Your Kong Konnect API token
   # - konnect_server_url: Your Konnect region URL (default: https://us.api.konghq.com)
   ```

   _Optionally, set the following variable via TF_VAR_konnect_token environment variable._

   ```bash
   export TF_VAR_konnect_token="your-konnect-api-token-here"
   ```

**Initialize and apply Terraform:**

1. Initialize Terraform (downloads providers)

   ```bash
   terraform -chdir=terraform init
   ```

2. Review the planned changes

   ```bash
   terraform -chdir=terraform plan
   ```

3. Apply the configuration (creates resources in Konnect)
   ```bash
   terraform -chdir=terraform apply
   ```

After successful application, Terraform will create:

- Event Gateway in Konnect
- Backend cluster configuration
- Three virtual clusters (Operations-Team, Analytics-Team, External-Partners)
- Internal and external listeners with TLS policies
- Encryption, schema validation, and record skipping policies

### 5. Deploy KEG

1. Create Konnect secret specific to your KEG control plane.

   ```bash
   kubectl create secret generic konnect-env-secret \
     --from-literal=KONNECT_REGION=$(terraform -chdir=terraform output -raw konnect_region) \
     --from-literal=KONNECT_DOMAIN=konghq.com \
     --from-literal=KONNECT_GATEWAY_CLUSTER_ID=$(terraform -chdir=terraform output -raw konnect_gateway_cluster_id) \
     --from-file=KONNECT_CLIENT_CERT=./terraform/certs/tls.crt \
     --from-file=KONNECT_CLIENT_KEY=./terraform/certs/key.crt \
     -n keg
   ```

2. Deploy KEG components and setup services and namespaces for the virtual clusters
   ```bash
   kubectl apply -f keg/
   ```

### 6. Configure Kong Ingress Controller (KIC) with TLSRoute support

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

### 7. Deploy Kafka Connect

1. Deploy Kafka Connect clusters

   ```bash
   kubectl apply -f kafka/kafka-connect/kafka-connect-operations.yaml -f kafka/kafka-connect/kafka-connect-analytics.yaml
   ```

2. Deploy Kafka Connect connectors
   ```bash
   kubectl apply -f kafka/kafka-connect/connectors/
   ```

### 8. Deploy Kafka UI

```bash
# Deploy Kafka UI
kubectl apply -f kafka-ui/
```

### 9. Deploy Observability Stack

1. Deploy observability components (Jaeger, Prometheus, OpenTelemetry Collector)

   > Note: Deploy Jaeger first as the OTEL collector references it
   > All observability components are deployed in the observability namespace

   ```bash
   kubectl apply -f observability/jaeger.yaml
   kubectl apply -f observability/prometheus.yaml
   kubectl apply -f observability/otel-collector.yaml
   ```

2. Deploy HTTPRoutes for accessing observability UIs
   ```bash
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

### 10. Ensure loadbalancer service is accessible

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
