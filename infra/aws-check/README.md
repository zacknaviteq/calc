# calc in AWS Check (899796413445, eu-north-1)

Managed by OpsAgent runbooks. State: `s3://opsagent-tf-state-12bbcef4/calc/aws-check/terraform.tfstate`.

- EC2 `calc-app` (t4g.micro, AL2023 arm64, Docker) behind an Elastic IP, no SSH (SSM only). Port 80 is **closed to the internet**; allow specific networks with `allowed_http_cidrs`.
- On first boot the instance builds `main` from GitHub and runs it on port 80.
- `/usr/local/bin/calc-deploy [s3://.../app.tgz]` rebuilds and restarts the container (used by the deploy pipeline).
- S3 `calc-deploy-artifacts-899796413445`: pipeline artifacts, expire after 30 days.

The legacy `infra/` unit (account 960410382237, us-east-1) is separate and not touched by this directory.
