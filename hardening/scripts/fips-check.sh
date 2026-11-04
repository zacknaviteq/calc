#!/usr/bin/env bash
# FIPS 140-3 readiness check for an image.
#   fips-check.sh <rootfs-dir> <image-ref> <out.json>
# Static checks read the exported root filesystem; runtime checks run the
# image's own openssl (if present) with no network.
set -uo pipefail
ROOTFS=$1 IMAGE=$2 OUT=$3

run_in() { # entrypoint args...
  if [ -n "${CHROOT_TEST:-}" ]; then
    chroot "$ROOTFS" env OPENSSL_FORCE_FIPS_MODE=1 "$@"
  else
    docker run --rm -i --network none --user 1001:1001 --entrypoint "$1" "$IMAGE" "${@:2}"
  fi
}

declare -a checks=()
add() { checks+=("$(jq -nc --arg id "$1" --arg desc "$2" --arg result "$3" --arg detail "$4" '{id:$id,desc:$desc,result:$result,detail:$detail}')"); }

# 1. Validated FIPS provider module present
mod=$(find "$ROOTFS/usr/lib64/ossl-modules" "$ROOTFS/usr/lib/ossl-modules" -name fips.so 2>/dev/null | head -1)
if [ -n "$mod" ]; then
  add fips_provider_present "OpenSSL FIPS provider module (fips.so) is installed" pass "${mod#"$ROOTFS"}"
else
  add fips_provider_present "OpenSSL FIPS provider module (fips.so) is installed" fail "no fips.so found (Alpine/musl images ship no FIPS-validated OpenSSL)"
fi

# 2. System crypto policy
cp_cfg=$(grep -v '^#' "$ROOTFS/etc/crypto-policies/config" 2>/dev/null | head -1)
cp_cur=$(cat "$ROOTFS/etc/crypto-policies/state/current" 2>/dev/null | head -1)
if [[ "$cp_cfg" == FIPS* && "$cp_cur" == FIPS* ]]; then
  add crypto_policy_fips "System-wide crypto policy is FIPS" pass "config=$cp_cfg current=$cp_cur"
else
  add crypto_policy_fips "System-wide crypto policy is FIPS" fail "config=${cp_cfg:-absent} current=${cp_cur:-absent}"
fi

# 3. Runtime: FIPS provider active, non-approved algorithm refused, approved works
if [ -x "$ROOTFS/usr/bin/openssl" ]; then
  prov=$(run_in /usr/bin/openssl list -providers 2>&1)
  if grep -A3 -E '^\s+fips$' <<<"$prov" | grep -q 'status: active'; then
    add fips_provider_active "FIPS provider is loaded and active at runtime" pass "$(grep -A2 -E '^\s+fips$' <<<"$prov" | grep name | sed 's/^ *//')"
  else
    add fips_provider_active "FIPS provider is loaded and active at runtime" fail "$(tr '\n' ' ' <<<"$prov" | cut -c1-300)"
  fi
  if echo test | run_in /usr/bin/openssl md5 >/dev/null 2>&1; then
    add md5_refused "Non-approved algorithm (MD5) is refused" fail "openssl md5 succeeded"
  else
    add md5_refused "Non-approved algorithm (MD5) is refused" pass "openssl md5 rejected (unsupported in FIPS mode)"
  fi
  if echo test | run_in /usr/bin/openssl sha256 >/dev/null 2>&1; then
    add sha256_works "Approved algorithm (SHA-256) works" pass "openssl sha256 succeeded"
  else
    add sha256_works "Approved algorithm (SHA-256) works" fail "openssl sha256 failed"
  fi
else
  add fips_provider_active "FIPS provider is loaded and active at runtime" fail "no openssl CLI in image; nothing FIPS-capable to test"
fi

# 4. Server binary links the system OpenSSL (not a bundled/static crypto lib)
if [ -x "$ROOTFS/usr/sbin/nginx" ] && grep -q 'libssl.so.3' <(strings "$ROOTFS/usr/sbin/nginx" 2>/dev/null); then
  lib=$(find "$ROOTFS/usr/lib64" -maxdepth 1 -name 'libssl.so.3*' 2>/dev/null | head -1)
  if [ -n "$lib" ] && [ -n "$mod" ]; then
    add nginx_uses_system_openssl "nginx is linked against the system OpenSSL 3 (FIPS provider capable)" pass "${lib#"$ROOTFS"}"
  else
    add nginx_uses_system_openssl "nginx is linked against the system OpenSSL 3 (FIPS provider capable)" fail "libssl present but no FIPS provider"
  fi
else
  add nginx_uses_system_openssl "nginx is linked against the system OpenSSL 3 (FIPS provider capable)" fail "nginx not linked to a FIPS-capable OpenSSL"
fi

printf '%s\n' "${checks[@]}" | jq -s '{
  checks: .,
  passed: (map(select(.result=="pass"))|length),
  failed: (map(select(.result=="fail"))|length),
  result: (if all(.result=="pass") then "pass" else "fail" end),
  note: "Image-level FIPS readiness. Full FIPS mode also requires the host kernel booted with fips=1 (out of scope for this pipeline)."
}' > "$OUT"
jq -r '"FIPS: \(.result) (\(.passed) passed, \(.failed) failed)"' "$OUT"
