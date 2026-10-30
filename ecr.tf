resource "aws_ecr_repository" "app" {
  name                 = "${var.project}/application"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project}-application-ecr"
  }
}
