# Kubernetes Demo Backends — Deployment Guide

Deploy Swagger Petstore and Podinfo to the AKS cluster created by the Bicep modules in `infra/`. These backends are accessible via an Azure internal load balancer, which is fronted by a Private Link Service for APIM connectivity.

## Architecture

```
AFD → APIM (Private Endpoint) → Private Link Service → Internal LB → ClusterIP Services
                                                            │
                                                     ┌──────┴──────┐
                                                     │             │
                                                Port 8080      Port 9898
                                                 Petstore       Podinfo
```

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| kubectl | 1.27+ | `az aks install-cli` |
| helm | 3.12+ | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| az cli | 2.50+ | [docs.microsoft.com](https://docs.microsoft.com/cli/azure/install-azure-cli) |

### Connect to AKS

```bash
az login
az aks get-credentials --resource-group <resource-group> --name <aks-cluster-name>
kubectl get nodes  # verify connectivity
```

## Quick Start

```bash
cd infra/k8s
chmod +x deploy.sh
./deploy.sh
```

The script will:
1. Create the `demo-apis` namespace
2. Install Petstore (2 replicas, port 8080)
3. Install Podinfo (2 replicas, port 9898)
4. Install the internal load balancer
5. Wait for the LB to get an internal IP
6. Print the IP and next steps

## Manual Deployment

### 1. Generate TLS Certificates

```bash
cd ../modules/aks
chmod +x generate-self-signed-cert.sh
./generate-self-signed-cert.sh ./certs backend.internal.aks.demo
```

### 2. Create TLS Secrets

```bash
kubectl create namespace demo-apis

# Create secrets from generated certs
kubectl create secret tls petstore-tls \
  --cert=certs/server.crt --key=certs/server.key -n demo-apis

kubectl create secret tls podinfo-tls \
  --cert=certs/server.crt --key=certs/server.key -n demo-apis
```

### 3. Install Charts

```bash
cd infra/k8s

helm upgrade --install demo-petstore ./petstore \
  --namespace demo-apis --wait

helm upgrade --install demo-podinfo ./podinfo \
  --namespace demo-apis --wait

helm upgrade --install demo-internal-lb ./internal-lb \
  --namespace demo-apis --wait
```

## Verification

### Check pods are running

```bash
kubectl get pods -n demo-apis
# Expected: 2/2 Running for both petstore and podinfo
```

### Check services

```bash
kubectl get svc -n demo-apis
# Expected: ClusterIP services + LoadBalancer with EXTERNAL-IP
```

### Test from inside the cluster

```bash
# Petstore
kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://<INTERNAL-LB-IP>:8080/api/v3/openapi.json | head -5

# Podinfo
kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://<INTERNAL-LB-IP>:9898/healthz
```

## Get Internal LB IP (for APIM configuration)

```bash
kubectl get svc demo-internal-lb-petstore -n demo-apis \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

This IP is used in:
- **Private Link Service** Bicep module (`aksLoadBalancerFrontendIpConfigId`)
- **APIM backend** configuration (service URL)

## Import Petstore OpenAPI into APIM

Once backends are running and APIM can reach them via Private Link:

```bash
# From within the cluster or a jump box with access to the internal LB
SPEC_URL="http://<INTERNAL-LB-IP>:8080/api/v3/openapi.json"

az apim api import \
  --resource-group <rg> \
  --service-name <apim-name> \
  --api-id petstore-v3 \
  --path petstore \
  --specification-url "${SPEC_URL}" \
  --specification-format OpenApiJson \
  --display-name "Petstore v3"
```

For Podinfo, create a manual API definition since it doesn't have an OpenAPI spec:
```bash
az apim api create \
  --resource-group <rg> \
  --service-name <apim-name> \
  --api-id podinfo \
  --path podinfo \
  --display-name "Podinfo" \
  --service-url "http://<INTERNAL-LB-IP>:9898" \
  --protocols https
```

## Troubleshooting

### Pods not starting

```bash
# Check events
kubectl describe pod -l app.kubernetes.io/name=petstore -n demo-apis

# Check logs
kubectl logs -l app.kubernetes.io/name=petstore -n demo-apis --tail=50
```

### Load Balancer stuck in Pending

```bash
# Verify AKS has permission to create LBs
kubectl describe svc demo-internal-lb-petstore -n demo-apis

# Common causes:
# - AKS identity lacks Network Contributor on the subnet
# - Subnet is full (check IP availability)
# - NSG blocking LB health probes
```

### APIM cannot reach backends

1. Verify Private Link Service is connected:
   ```bash
   az network private-link-service show -g <rg> -n <pls-name> --query "privateEndpointConnections"
   ```

2. Verify the LB frontend IP config matches what PLS expects:
   ```bash
   kubectl get svc demo-internal-lb-petstore -n demo-apis -o yaml | grep -A5 "status:"
   ```

3. Test connectivity from a pod in the same VNet:
   ```bash
   kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \
     curl -v http://<LB-IP>:8080/api/v3/openapi.json
   ```

### TLS/mTLS issues

```bash
# Verify cert is mounted
kubectl exec -it <pod-name> -n demo-apis -- ls /etc/tls/

# Check cert details
kubectl get secret petstore-tls -n demo-apis -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text
```

## Cleanup

```bash
helm uninstall demo-petstore demo-podinfo demo-internal-lb -n demo-apis
kubectl delete namespace demo-apis
```
