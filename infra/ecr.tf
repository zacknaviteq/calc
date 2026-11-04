resource "aws_ecr_repository" "calc" {
  name                 = var.name
  image_tag_mutability = "MUTABLE" # "latest" is re-pointed on every deploy

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "calc" {
  repository = aws_ecr_repository.calc.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last ${var.ecr_images_to_keep} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_images_to_keep
      }
      action = { type = "expire" }
    }]
  })
}
