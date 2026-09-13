# Private registry for the Foundry image.
#
# The image contains licensed Foundry software and must never reach a public
# registry. The instance builds and pushes it itself (REQUIREMENTS.md R13).

resource "aws_ecr_repository" "foundry" {
  name         = var.name_prefix
  force_delete = var.ecr_force_delete

  # Immutable tags pair with the build-if-absent logic in boot.sh: a version
  # is built once and never silently changes underneath you.
  #
  # Consequence worth knowing: editing the Dockerfile does NOT rebuild an
  # image that already exists in ECR. To pick up a Dockerfile change you must
  # either bump foundry_version or delete the existing tag from ECR.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "foundry" {
  repository = aws_ecr_repository.foundry.name

  # Images are ~1-2GB. Keeping every historical build is a quiet cost.
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 3 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}
