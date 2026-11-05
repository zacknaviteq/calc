# calc image hardening (STIG + FIPS)

`.github/workflows/harden.yml` takes an image from ECR `calc`, rebuilds it onto Red Hat UBI 9, and scans it before and after. If the gate passes, it pushes a signed image to ECR `hardened-images`. Evidence goes to S3 (Object Lock), and everything is posted to Slack.

Alpine (the source base) has no STIG/SCAP content and no FIPS-validated OpenSSL, so hardening means a rebuild: same static site, served by RHEL 9 nginx linked to the FIPS 140-3 validated OpenSSL provider.

## Triggers
- After **Build and deploy** succeeds on `main`. It hardens the commit that was just deployed.
- Manual: **Actions → Harden image → Run workflow**. `source` takes a `calc` tag (commit SHA / `latest`) or a `sha256:` digest.
- Weekly, Monday 06:00 UTC, on `calc:latest`. This picks up new UBI errata.

## Pipeline
1. **BEFORE** (source image, pulled by digest): Trivy (CVE/secret/misconfig), Syft SBOM (SPDX + CycloneDX), Dockle (CIS Docker), OpenSCAP RHEL 9 STIG, FIPS checks.
2. **Build** (`Containerfile`): pinned `ubi9/ubi` builder + `ubi9/ubi-micro` rootfs, then `dnf upgrade` (all errata) and install of nginx 1.26 + FIPS provider only. Next it sets crypto policy `FIPS`, applies `stig-remediate.sh` (non-root uid 1001, umask 077, locked accounts, setuid stripped, package manager removed) and `nginx.conf` (port 8080, security headers, GET/HEAD only, request limits, no dotfiles). The final image is `FROM scratch`.
3. **Smoke test**: read-only root fs, `--cap-drop ALL`, `no-new-privileges`.
4. **AFTER**: the same scans, plus a before/after diff.
5. **Gate** (all must pass): no fixable CRITICAL CVEs, no secrets, STIG pass rate ≥ 95%, 0 STIG fails and 0 CAT I, FIPS checks pass, Dockle no FATAL, non-root, smoke test.
6. **Push** `hardened-images:calc-<sha12>-<run>`, then `cosign` keyless sign + SPDX SBOM attestation + OpenSCAP result attestation, then verify.
7. **Evidence** zip (raw scanner output, HTML STIG reports, SBOMs, build log, tailoring, manifest, `SHA256SUMS`) → `s3://calc-hardening-evidence-960410382237/calc/<sha>/<run>/`, plus an Actions artifact.
8. **Slack**: summary in `#zack-dave-testing`, with the before report, after report, STIG HTML and evidence zip in the thread.

## STIG tailoring (`stig-tailoring.xml`)
Profile `xccdf_org.ssgproject.content_profile_stig` (DISA STIG for RHEL 9, SSG 0.1.82), with the following changes:
- `var_system_crypto_policy` is `FIPS`, not `FIPS:STIG`. UBI 9 crypto-policies does not ship the `STIG` sub-policy.
- `network_configure_name_resolution` is deselected. `resolv.conf` is supplied by the container runtime.

Host-only rules (kernel, boot, auditd, sshd, PAM, partitions) evaluate as *not applicable* to a container image.

## FIPS scope
The image ships, and at runtime enforces (`OPENSSL_FORCE_FIPS_MODE=1`), the RHEL 9 OpenSSL FIPS provider. Full FIPS mode also needs the host kernel booted with `fips=1`, which is out of scope here.

## Running the hardened image
It listens on **8080** as uid 1001. Example: `docker run -p 80:8080 --read-only --cap-drop ALL --tmpfs /run/nginx:uid=1001,gid=1001 --tmpfs /var/lib/nginx/tmp:uid=1001,gid=1001 <image>`.

Verify the signature:
```sh
cosign verify \
  --certificate-identity-regexp '^https://github.com/zacknaviteq/calc/.github/workflows/harden.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  960410382237.dkr.ecr.us-east-1.amazonaws.com/hardened-images:<tag>
```

## Setup
| Item | Value |
|---|---|
| Secret `SLACK_BOT_TOKEN` | Slack bot token with `chat:write` + `files:write`; bot invited to `#zack-dave-testing` |
| Variable `HARDEN_ROLE_ARN` | `terraform output github_harden_role_arn` (defaults to `arn:aws:iam::960410382237:role/calc-github-harden`) |
| Variable `HARDEN_EVIDENCE_BUCKET` (optional) | `terraform output hardening_evidence_bucket` |
| Variable `HARDEN_SLACK_CHANNEL_ID` (optional) | defaults to `C0CE6TC357B` |

## Pinned versions
Trivy 0.76.1, Dockle 0.4.15, Syft 1.56.0, cosign 3.1.4 (all sha256-verified in `scripts/install-tools.sh`). OpenSCAP 1.3.14-1.el9_8 and SSG 0.1.82 (sha256-verified, `scanner/Containerfile`). UBI 9.8 bases are pinned by digest. Actions are pinned by commit SHA.
