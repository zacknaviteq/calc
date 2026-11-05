#!/usr/bin/env bash
# Installs pinned, checksum-verified scanner tools into $1 (default ./.tools/bin).
set -euo pipefail
BIN=${1:-.tools/bin}
mkdir -p "$BIN"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fetch() { # url sha256 out
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c -
}

TRIVY_VERSION=0.76.1
fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
  c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0 "$TMP/trivy.tgz"
tar -xzf "$TMP/trivy.tgz" -C "$BIN" trivy

DOCKLE_VERSION=0.4.15
fetch "https://github.com/goodwithtech/dockle/releases/download/v${DOCKLE_VERSION}/dockle_${DOCKLE_VERSION}_Linux-64bit.tar.gz" \
  8bfc9183d1d3d67800edb45bea4bb63ddf1d28bec5f89944075a07007d79caad "$TMP/dockle.tgz"
tar -xzf "$TMP/dockle.tgz" -C "$BIN" dockle

SYFT_VERSION=1.56.0
fetch "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_amd64.tar.gz" \
  1c2493cfcf52d3367d6cb25780d9190c111c2219c34c820574c43e8bae15c528 "$TMP/syft.tgz"
tar -xzf "$TMP/syft.tgz" -C "$BIN" syft

COSIGN_VERSION=3.1.4
fetch "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" \
  424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa "$BIN/cosign"
chmod 0755 "$BIN/cosign"

"$BIN/trivy" --version | head -1
"$BIN/dockle" --version
"$BIN/syft" version | grep -m1 '^Version'
"$BIN/cosign" version 2>&1 | grep -m1 GitVersion
