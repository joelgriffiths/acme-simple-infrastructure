# Per-environment container registry. Staging and prod each own their repositories so no
# pull ever crosses an environment boundary; the build pipeline uses skopeo to copy the
# image between them, which preserves the digest. Consolidating onto a single acme-tools
# registry account is an EVOLUTION step, not a today problem.
#
# Security controls that matter here: scan on push, immutable tags (a deployed tag can
# never be re-pointed at different bytes), KMS encryption, and a lifecycle policy so old
# images age out instead of accumulating.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = { Name = "${var.name_prefix}/${each.value}" }
}

# Keep the last N tagged images, and drop untagged layers quickly.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the most recent ${var.retained_image_count} tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.retained_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

# Only this account's ECS execution roles pull from here. No cross-account grant: the
# pipeline pushes with its own credentials, and images move between environments by an
# explicit skopeo copy rather than by one environment reading another's registry.
data "aws_iam_policy_document" "repo" {
  statement {
    sid    = "AllowLocalAccountPull"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
  }
}

resource "aws_ecr_repository_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy     = data.aws_iam_policy_document.repo.json
}
