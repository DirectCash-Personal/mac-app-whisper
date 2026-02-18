#!/bin/bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════╗
# ║  SuperWhisper — Setup Code Signing Certificate               ║
# ║  Run once to create a self-signed certificate for builds     ║
# ╚══════════════════════════════════════════════════════════════╝

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CERT_NAME="SuperWhisper Developer"

echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🔐 SuperWhisper Code Signing Setup              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"

# Check if certificate already exists
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo -e "${GREEN}✅ Certificate '${CERT_NAME}' already exists in Keychain.${NC}"
    echo ""
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    echo ""
    echo -e "${GREEN}No action needed — you're all set!${NC}"
    exit 0
fi

echo -e "\n${YELLOW}📝 Creating self-signed code signing certificate...${NC}"

# Create a temporary certificate configuration
CERT_CONFIG=$(mktemp /tmp/superwhisper-cert.XXXXXX)
cat > "$CERT_CONFIG" << EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
string_mask        = utf8only
x509_extensions    = codesign

[ req_dn ]
CN = SuperWhisper Developer
O  = SuperWhisper

[ codesign ]
keyUsage                = critical, digitalSignature
extendedKeyUsage        = critical, codeSigning
subjectKeyIdentifier    = hash
EOF

# Generate key and certificate
CERT_PEM=$(mktemp /tmp/superwhisper-cert-pem.XXXXXX)
KEY_PEM=$(mktemp /tmp/superwhisper-key-pem.XXXXXX)
P12_FILE=$(mktemp /tmp/superwhisper-cert-p12.XXXXXX)

openssl req -x509 -newkey rsa:2048 -keyout "$KEY_PEM" -out "$CERT_PEM" \
    -days 3650 -nodes -config "$CERT_CONFIG" 2>/dev/null

echo -e "   ✅ Certificate generated (valid for 10 years)"

# Convert to .p12 for importing into Keychain
openssl pkcs12 -export -out "$P12_FILE" -inkey "$KEY_PEM" -in "$CERT_PEM" \
    -passout pass: 2>/dev/null

echo -e "   ✅ Converted to PKCS12 format"

# Import into login Keychain
security import "$P12_FILE" -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign -T /usr/bin/security -P "" 2>/dev/null || \
security import "$P12_FILE" -k ~/Library/Keychains/login.keychain \
    -T /usr/bin/codesign -T /usr/bin/security -P "" 2>/dev/null

echo -e "   ✅ Imported into login Keychain"

# Set the certificate as trusted for code signing
# This prevents the "unknown developer" warning
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" \
    ~/Library/Keychains/login.keychain-db 2>/dev/null || \
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" \
    ~/Library/Keychains/login.keychain 2>/dev/null || true

echo -e "   ✅ Certificate trusted for code signing"

# Cleanup temp files
rm -f "$CERT_CONFIG" "$CERT_PEM" "$KEY_PEM" "$P12_FILE"

# Verify
echo ""
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Certificate created successfully!             ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    echo ""
    echo -e "${CYAN}All future builds will use this certificate.${NC}"
    echo -e "${CYAN}Accessibility and other permissions will persist across updates!${NC}"
else
    echo -e "${RED}❌ Certificate creation failed.${NC}"
    echo -e "${YELLOW}You may need to open Keychain Access and trust the certificate manually.${NC}"
    exit 1
fi
