# calc infra

Terraform for the calc app: ECR repo, t2.micro EC2 (AL2023, Docker) with an Elastic IP,
SSM-only access (no SSH), and a GitHub OIDC deploy role scoped to `repo:zacknaviteq/calc:ref:refs/heads/main`.

State: `s3://calc-tfstate-960410382237/calc/infra/terraform.tfstate` (versioned, encrypted, S3 native locking).

```sh
cd infra
terraform init
terraform plan
terraform apply
```

After apply, set these GitHub repo variables from the outputs:

| Variable          | Value                                 |
|-------------------|---------------------------------------|
| `AWS_ROLE_ARN`    | `terraform output github_deploy_role_arn` |
| `AWS_REGION`      | `us-east-1`                           |
| `EC2_INSTANCE_ID` | `terraform output instance_id`        |
| `ECR_REPOSITORY`  | `terraform output ecr_repository`     |

Manual redeploy on the instance (SSM Session Manager): `sudo /usr/local/bin/calc-deploy`.

Rollback: `terraform destroy`.

## Image hardening (`hardening.tf`)
ECR `hardened-images`, the evidence bucket `calc-hardening-evidence-<account>` (Object Lock governance 365d, Glacier after 90d) and the OIDC role `calc-github-harden` used by `.github/workflows/harden.yml`. Set the repo variable `HARDEN_ROLE_ARN` from `terraform output github_harden_role_arn`. See `hardening/README.md`.

The evidence bucket has Object Lock, so `terraform destroy` cannot delete it while locked objects exist.
