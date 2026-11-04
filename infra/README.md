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
