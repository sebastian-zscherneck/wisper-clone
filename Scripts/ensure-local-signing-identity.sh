#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="Wisper Clone Local Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TEMP_DIR="$(mktemp -d)"
KEY_FILE="$TEMP_DIR/wisper-clone-local-signing.key"
CERT_FILE="$TEMP_DIR/wisper-clone-local-signing.cer"
P12_FILE="$TEMP_DIR/wisper-clone-local-signing.p12"
P12_PASSWORD="wisper-clone-local"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if security find-identity -v -p codesigning | grep -Fq "$IDENTITY_NAME"; then
    echo "$IDENTITY_NAME"
    exit 0
fi

openssl req \
    -newkey rsa:2048 \
    -nodes \
    -keyout "$KEY_FILE" \
    -x509 \
    -days 3650 \
    -out "$CERT_FILE" \
    -subj "/CN=$IDENTITY_NAME/" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

openssl pkcs12 \
    -export \
    -legacy \
    -inkey "$KEY_FILE" \
    -in "$CERT_FILE" \
    -out "$P12_FILE" \
    -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import "$P12_FILE" \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$CERT_FILE" >/dev/null

echo "$IDENTITY_NAME"
