# Private staging bucket used only by scripts/final-export.sh to get the
# Neo4j/Postgres dump off the instance (no SSH/SCP - the instance has no open
# admin port). Destroyed along with everything else by `terraform destroy`;
# final-export.sh downloads locally and deletes the object before that happens.
resource "aws_s3_bucket" "exports" {
  bucket = "${var.project_name}-exports-${random_string.bucket_suffix.result}"
}

resource "aws_s3_bucket_public_access_block" "exports" {
  bucket                  = aws_s3_bucket.exports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role_policy" "ec2_export_upload" {
  name = "${var.project_name}-ec2-export-upload"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.exports.arn}/*"
    }]
  })
}

output "exports_bucket_name" {
  value = aws_s3_bucket.exports.bucket
}
