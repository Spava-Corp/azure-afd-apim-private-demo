#!/usr/bin/env bash
# ============================================================================
# deploy.sh — Deploy demo backends to AKS
# Installs Petstore + Podinfo + Internal LB via Helm
# Author: Sydnor (Platform Dev)
# ============================================================================
set -euo pipefail

NAMESPACE="${1:-demo-apis}"
RELEASE_PREFIX="${2:-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  AKS Demo Backend Deployment"
echo "  Namespace: ${NAMESPACE}"
echo "  Release prefix: ${RELEASE_PREFIX}"
echo "============================================"
echo ""

# --- Prerequisites check ---
for cmd in kubectl helm; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: ${cmd} is required but not found in PATH."
        exit 1
    fi
done

# Verify cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster."
    echo "Run: az aks get-credentials --resource-group <rg> --name <cluster>"
    exit 1
fi

echo "✓ Connected to cluster: $(kubectl config current-context)"
echo ""

# --- Create namespace ---
echo "[1/5] Creating namespace '${NAMESPACE}'..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo "  ✓ Namespace ready"
echo ""

# --- Install Petstore ---
echo "[2/5] Installing Petstore chart..."
helm upgrade --install "${RELEASE_PREFIX}-petstore" "${SCRIPT_DIR}/petstore" \
    --namespace "${NAMESPACE}" \
    --set replicaCount=2 \
    --wait --timeout 120s
echo "  ✓ Petstore deployed"
echo ""

# --- Install Podinfo ---
echo "[3/5] Installing Podinfo chart..."
helm upgrade --install "${RELEASE_PREFIX}-podinfo" "${SCRIPT_DIR}/podinfo" \
    --namespace "${NAMESPACE}" \
    --set replicaCount=2 \
    --wait --timeout 120s
echo "  ✓ Podinfo deployed"
echo ""

# --- Install Internal Load Balancer ---
echo "[4/5] Installing Internal Load Balancer..."
helm upgrade --install "${RELEASE_PREFIX}-internal-lb" "${SCRIPT_DIR}/internal-lb" \
    --namespace "${NAMESPACE}" \
    --wait --timeout 120s
echo "  ✓ Internal LB deployed"
echo ""

# --- Wait for LB IP ---
echo "[5/5] Waiting for internal LB to receive an IP address..."
LB_SVC="demo-internal-lb-petstore"
TIMEOUT=120
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    LB_IP=$(kubectl get svc "${LB_SVC}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$LB_IP" ]; then
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  ... waiting (${ELAPSED}s/${TIMEOUT}s)"
done

if [ -z "${LB_IP:-}" ]; then
    echo "  ⚠️  Timed out waiting for LB IP. Check with:"
    echo "     kubectl get svc -n ${NAMESPACE}"
    exit 1
fi

echo ""
echo "============================================"
echo "  ✅ Deployment Complete!"
echo "============================================"
echo ""
echo "  Internal LB IP: ${LB_IP}"
echo ""
echo "  Backends:"
echo "    Petstore: http://${LB_IP}:8080/api/v3/openapi.json"
echo "    Podinfo:  http://${LB_IP}:9898/"
echo ""
echo "  Next steps:"
echo "    1. Use this IP in the Bicep Private Link Service module"
echo "       (aksLoadBalancerFrontendIpConfigId parameter)"
echo "    2. Configure APIM backends to point to this IP"
echo "    3. Import Petstore OpenAPI spec into APIM:"
echo "       az apim api import --path petstore \\"
echo "         --api-id petstore-v3 \\"
echo "         --specification-url http://${LB_IP}:8080/api/v3/openapi.json \\"
echo "         --specification-format OpenApi"
echo ""
echo "  Verify from within the cluster:"
echo "    kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \\"
echo "      curl -s http://${LB_IP}:8080/api/v3/openapi.json | head -20"
echo ""
echo "    kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \\"
echo "      curl -s http://${LB_IP}:9898/healthz"
echo ""

# --- Summary ---
echo "  Pod status:"
kubectl get pods -n "${NAMESPACE}" -o wide
echo ""
echo "  Services:"
kubectl get svc -n "${NAMESPACE}"
