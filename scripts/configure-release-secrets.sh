#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-burakereno/youtubejack}"
P12_PATH="${P12_PATH:-/Users/burakerenoglu/Desktop/Certificates.p12}"
TEAM_ID="${APPLE_TEAM_ID:-66K3EFBVB6}"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

if [ ! -f "$P12_PATH" ]; then
  echo "P12 file not found: $P12_PATH" >&2
  exit 1
fi

printf "YouTubeJack release secret setup\n"
printf "Repo: %s\n" "$REPO"
printf "P12: %s\n" "$P12_PATH"
printf "Team ID: %s\n\n" "$TEAM_ID"

IFS= read -r -s -p "P12 export password (press Enter if empty): " P12_PASSWORD
printf "\n"
IFS= read -r -p "Apple ID email: " APPLE_ID
IFS= read -r -s -p "Apple app-specific password: " APPLE_APP_SPECIFIC_PASSWORD
printf "\n\n"

if [ -z "$APPLE_ID" ]; then
  echo "Apple ID email cannot be empty." >&2
  exit 1
fi

if [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
  echo "Apple app-specific password cannot be empty." >&2
  exit 1
fi

KEYCHAIN_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
TMP_KEYCHAIN="${TMPDIR:-/tmp}/youtubejack-secret-check-$$.keychain-db"

cleanup() {
  security delete-keychain "$TMP_KEYCHAIN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf "Checking P12 for a Developer ID Application identity...\n"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$TMP_KEYCHAIN" >/dev/null
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$TMP_KEYCHAIN" >/dev/null
security import "$P12_PATH" \
  -P "$P12_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$TMP_KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$TMP_KEYCHAIN" >/dev/null 2>&1 || true

IDENTITY="$(security find-identity -v -p codesigning "$TMP_KEYCHAIN" | awk '/Developer ID Application/ { print $2; exit }')"
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application identity was found in this P12." >&2
  security find-identity -v -p codesigning "$TMP_KEYCHAIN" >&2 || true
  exit 1
fi
printf "Developer ID Application found: %s\n" "$IDENTITY"

printf "Writing GitHub Secrets...\n"
base64 -i "$P12_PATH" | gh secret set MACOS_CERTIFICATE_P12_BASE64 --repo "$REPO" --body-file - >/dev/null
printf "%s" "$P12_PASSWORD" | gh secret set MACOS_CERTIFICATE_PASSWORD --repo "$REPO" --body-file - >/dev/null
printf "%s" "$KEYCHAIN_PASSWORD" | gh secret set KEYCHAIN_PASSWORD --repo "$REPO" --body-file - >/dev/null
printf "%s" "$APPLE_ID" | gh secret set APPLE_ID --repo "$REPO" --body-file - >/dev/null
printf "%s" "$TEAM_ID" | gh secret set APPLE_TEAM_ID --repo "$REPO" --body-file - >/dev/null
printf "%s" "$APPLE_APP_SPECIFIC_PASSWORD" | gh secret set APPLE_APP_SPECIFIC_PASSWORD --repo "$REPO" --body-file - >/dev/null

printf "Done. Release signing and notarization secrets are configured for %s.\n" "$REPO"
