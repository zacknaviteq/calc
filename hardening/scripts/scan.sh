#!/usr/bin/env bash
# Runs every scanner against one image and writes raw results to $W/<stage>/.
#   scan.sh <before|after> <image-ref>
# Needs: docker, trivy, dockle, syft on PATH; harden-scanner image built.
set -euo pipefail
STAGE=$1 IMG=$2
OUT="$W/$STAGE"; mkdir -p "$OUT" "$W/images"
TAR="$W/images/$STAGE.tar"
ROOTFS="$RUNNER_TEMP/rootfs-$STAGE"
HERE=$(cd "$(dirname "$0")" && pwd)

docker save -o "$TAR" "$IMG"

echo "::group::Trivy ($STAGE)"
trivy image --quiet --input "$TAR" --scanners vuln,secret,misconfig --format json -o "$OUT/trivy.json"
trivy convert --format table -o "$OUT/trivy.txt" "$OUT/trivy.json"
echo "::endgroup::"

echo "::group::Syft SBOM ($STAGE)"
syft scan "docker-archive:$TAR" -q -o "spdx-json=$OUT/sbom.spdx.json" -o "cyclonedx-json=$OUT/sbom.cdx.json"
echo "::endgroup::"

echo "::group::Dockle CIS ($STAGE)"
dockle --input "$TAR" --exit-code 0 -f json -o "$OUT/dockle.json"
echo "::endgroup::"

echo "::group::Export root filesystem ($STAGE)"
sudo rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"
cid=$(docker create "$IMG")
docker export "$cid" | sudo tar -xpf - -C "$ROOTFS" --exclude='dev/*'
docker rm "$cid" >/dev/null
sudo touch "$ROOTFS/.dockerenv" # mark the target as a container for SSG applicability
echo "::endgroup::"

echo "::group::OpenSCAP RHEL 9 STIG ($STAGE)"
rc=0
docker run --rm --network none \
  -v "$ROOTFS:/target:ro" -v "$OUT:/out" \
  -v "$GITHUB_WORKSPACE/hardening/stig-tailoring.xml:/work/tailoring.xml:ro" \
  harden-scanner xccdf eval \
    --tailoring-file /work/tailoring.xml \
    --profile xccdf_io.naviteq_profile_stig_container \
    --results /out/stig-results.xml --report /out/stig-report.html \
    /ssg/ssg-rhel9-ds.xml > "$OUT/stig-eval.txt" 2>&1 || rc=$?
# 0 = all pass, 2 = some rules failed, anything else is a scanner error.
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then cat "$OUT/stig-eval.txt"; echo "::error::oscap failed ($rc)"; exit 1; fi
grep '^Result' "$OUT/stig-eval.txt" | sort | uniq -c || true
echo "::endgroup::"

echo "::group::FIPS checks ($STAGE)"
bash "$HERE/fips-check.sh" "$ROOTFS" "$IMG" "$OUT/fips.json"
echo "::endgroup::"

user=$(docker image inspect -f '{{.Config.User}}' "$IMG"); user=${user:-root}
ports=$(docker image inspect -f '{{range $p, $_ := .Config.ExposedPorts}}{{$p}} {{end}}' "$IMG" | xargs)
size=$(docker image inspect -f '{{.Size}}' "$IMG")
smoke=$(cat "$OUT/smoke.result" 2>/dev/null || echo "n/a")
jq -n --arg image "${SOURCE_REF:-$IMG}" --arg digest "$(docker image inspect -f '{{.Id}}' "$IMG")" \
  --arg base "$(jq -r '.Metadata.OS | "\(.Family) \(.Name)"' "$OUT/trivy.json")" --arg user "$user" --arg ports "$ports" \
  --argjson size "$size" --argjson pkgs "$(jq '.packages | length' "$OUT/sbom.spdx.json")" --arg smoke "$smoke" \
  --arg at "$(date -u +%FT%TZ)" \
  '{image:$image, digest:$digest, base:$base, user:$user, ports:$ports, size_mb:(($size/1048576*10|round)/10),
    packages:$pkgs, smoke_test:$smoke, scanned_at:$at}' > "$OUT/meta.json"
sudo rm -rf "$ROOTFS"
