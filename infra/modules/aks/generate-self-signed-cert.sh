#!/usr/bin/env bash
# ============================================================================
# Self-Signed TLS Certificate Generator — AKS Backend (Demo Mode)
# Author: Kima (SecOps Engineer)
# Date: 2026-05-07
#
# Purpose: Generate a complete certificate chain for the AFD → APIM → AKS
# private architecture demo. Creates:
#   1. Root CA cert (signs everything)
#   2. Server cert (AKS backend presents to APIM)
#   3. Client cert (APIM presents to AKS for mTLS)
#
# WARNING: Self-signed certs are for DEMO/DEV only.
# In production, use Azure Key Vault with a proper CA (DigiCert, Let's Encrypt)
# or Azure's built-in managed certificates.
#
# Usage:
#   chmod +x generate-self-signed-cert.sh
#   ./generate-self-signed-cert.sh [output-dir] [backend-dns-name]
#
# Example:
#   ./generate-self-signed-cert.sh ./certs backend.internal.contoso.com
#
# Output files:
#   ca.key          — CA private key (PROTECT THIS)
#   ca.crt          — CA certificate (distribute to trust stores)
#   server.key      — Server private key (deploy to AKS pods)
#   server.crt      — Server certificate (deploy to AKS pods)
#   server.pfx      — Server cert bundle (for environments that need PKCS12)
#   client.key      — Client private key (upload to APIM/Key Vault)
#   client.crt      — Client certificate (upload to APIM/Key Vault)
#   client.pfx      — Client cert bundle (for APIM certificate store)
#   ca-chain.pem    — Full CA chain for verification
# ============================================================================

set -euo pipefail

# --- Configuration ---
OUTPUT_DIR="${1:-./certs}"
BACKEND_DNS="${2:-backend.internal.aks.demo}"
CA_DAYS=3650            # CA valid for 10 years (demo)
CERT_DAYS=365           # Server/client certs valid for 1 year
KEY_SIZE=4096           # RSA key size (2048 minimum, 4096 recommended)
CA_SUBJECT="/C=US/ST=Washington/L=Seattle/O=SecOps Demo/OU=Security/CN=SecOps Demo CA"
SERVER_SUBJECT="/C=US/ST=Washington/L=Seattle/O=SecOps Demo/OU=AKS Backend/CN=${BACKEND_DNS}"
CLIENT_SUBJECT="/C=US/ST=Washington/L=Seattle/O=SecOps Demo/OU=APIM Client/CN=apim-client"
PFX_PASSWORD="demo-only-change-me"  # Change in production!

# --- Validation ---
if ! command -v openssl &>/dev/null; then
    echo "ERROR: openssl is required but not installed."
    echo "Install: apt-get install openssl (Ubuntu) or brew install openssl (macOS)"
    exit 1
fi

echo "================================================"
echo "  Self-Signed Certificate Generator"
echo "  Output: ${OUTPUT_DIR}"
echo "  Backend DNS: ${BACKEND_DNS}"
echo "================================================"

# --- Create output directory ---
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"

# ============================================================================
# STEP 1: Generate Root CA
# The CA signs both server and client certs. In production, this would be
# an intermediate CA issued by your organization's root.
# ============================================================================
echo ""
echo "[1/3] Generating Root CA..."

openssl genrsa -out ca.key ${KEY_SIZE}
chmod 600 ca.key  # Restrict access to CA private key

openssl req -new -x509 \
    -key ca.key \
    -out ca.crt \
    -days ${CA_DAYS} \
    -subj "${CA_SUBJECT}" \
    -sha256

echo "  ✓ ca.key (private key — keep secure!)"
echo "  ✓ ca.crt (distribute to trust stores)"

# ============================================================================
# STEP 2: Generate Server Certificate (for AKS backend pods)
# This cert is presented by the backend when APIM connects over TLS.
# SAN (Subject Alternative Name) must match the DNS name APIM uses to connect.
# ============================================================================
echo ""
echo "[2/3] Generating Server Certificate for AKS backend..."

# Create server cert config with SANs
cat > server.cnf <<EOF
[req]
default_bits = ${KEY_SIZE}
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = US
ST = Washington
L = Seattle
O = SecOps Demo
OU = AKS Backend
CN = ${BACKEND_DNS}

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${BACKEND_DNS}
DNS.2 = *.${BACKEND_DNS}
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

# Generate server key and CSR
openssl genrsa -out server.key ${KEY_SIZE}
openssl req -new -key server.key -out server.csr -config server.cnf

# Sign with CA
openssl x509 -req \
    -in server.csr \
    -CA ca.crt \
    -CAkey ca.key \
    -CAcreateserial \
    -out server.crt \
    -days ${CERT_DAYS} \
    -sha256 \
    -extensions v3_req \
    -extfile server.cnf

# Create PFX bundle (for environments needing PKCS12 format)
openssl pkcs12 -export \
    -out server.pfx \
    -inkey server.key \
    -in server.crt \
    -certfile ca.crt \
    -passout "pass:${PFX_PASSWORD}"

echo "  ✓ server.key (deploy to AKS pods)"
echo "  ✓ server.crt (deploy to AKS pods)"
echo "  ✓ server.pfx (PKCS12 bundle, password: ${PFX_PASSWORD})"

# ============================================================================
# STEP 3: Generate Client Certificate (for APIM to present to AKS)
# APIM uses this cert to authenticate itself to the AKS backend (mTLS).
# Upload to Key Vault, reference in APIM authentication-certificate policy.
# ============================================================================
echo ""
echo "[3/3] Generating Client Certificate for APIM..."

# Create client cert config
cat > client.cnf <<EOF
[req]
default_bits = ${KEY_SIZE}
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = US
ST = Washington
L = Seattle
O = SecOps Demo
OU = APIM Client
CN = apim-client

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
EOF

# Generate client key and CSR
openssl genrsa -out client.key ${KEY_SIZE}
openssl req -new -key client.key -out client.csr -config client.cnf

# Sign with CA
openssl x509 -req \
    -in client.csr \
    -CA ca.crt \
    -CAkey ca.key \
    -CAcreateserial \
    -out client.crt \
    -days ${CERT_DAYS} \
    -sha256 \
    -extensions v3_req \
    -extfile client.cnf

# Create PFX bundle (APIM needs PKCS12 for certificate store upload)
openssl pkcs12 -export \
    -out client.pfx \
    -inkey client.key \
    -in client.crt \
    -certfile ca.crt \
    -passout "pass:${PFX_PASSWORD}"

echo "  ✓ client.key (upload to Key Vault)"
echo "  ✓ client.crt (upload to Key Vault)"
echo "  ✓ client.pfx (for APIM cert store, password: ${PFX_PASSWORD})"

# ============================================================================
# Create CA chain file (useful for verification)
# ============================================================================
cp ca.crt ca-chain.pem

# ============================================================================
# Cleanup CSR and temp files
# ============================================================================
rm -f server.csr client.csr server.cnf client.cnf ca.srl

# ============================================================================
# Verification
# ============================================================================
echo ""
echo "================================================"
echo "  Verification"
echo "================================================"
echo ""
echo "Server cert details:"
openssl x509 -in server.crt -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null || true
echo ""
echo "Client cert details:"
openssl x509 -in client.crt -noout -subject -issuer -dates -ext extendedKeyUsage 2>/dev/null || true
echo ""
echo "Verify server cert against CA:"
openssl verify -CAfile ca.crt server.crt
echo ""
echo "Verify client cert against CA:"
openssl verify -CAfile ca.crt client.crt

# ============================================================================
# Deployment Instructions
# ============================================================================
echo ""
echo "================================================"
echo "  Next Steps"
echo "================================================"
echo ""
echo "  1. AKS Backend (server cert):"
echo "     kubectl create secret tls backend-tls \\"
echo "       --cert=server.crt --key=server.key -n your-namespace"
echo ""
echo "  2. APIM (client cert for mTLS):"
echo "     az keyvault certificate import \\"
echo "       --vault-name <vault> --name apim-client-cert \\"
echo "       --file client.pfx --password '${PFX_PASSWORD}'"
echo ""
echo "  3. Trust Store (CA cert):"
echo "     Upload ca.crt to any system that needs to verify these certs"
echo ""
echo "  4. APIM Policy (enable mTLS):"
echo "     Uncomment authentication-certificate in apim-policies.xml"
echo ""
echo "  ⚠️  SECURITY REMINDER:"
echo "     - Rotate certs before expiry (${CERT_DAYS} days)"
echo "     - In production, use a real CA via Key Vault"
echo "     - Never commit private keys (.key files) to source control"
echo "     - Change the PFX password from the demo default"
echo ""
echo "Done! Certificates generated in: $(pwd)"
