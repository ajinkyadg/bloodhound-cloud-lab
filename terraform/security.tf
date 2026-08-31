# Deny-all inbound by default. The launch/stop/idle-check Lambdas add and remove
# a single-IP ingress rule on var.bloodhound_port at runtime via the EC2 API -
# no static ingress rules are declared here on purpose.
resource "aws_security_group" "bloodhound" {
  name        = "${var.project_name}-sg"
  description = "BloodHound instance SG. Ingress managed dynamically by Lambda, not Terraform."
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Allow all outbound (docker pulls, SSM agent, apt)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg" }

  lifecycle {
    ignore_changes = [ingress] # ingress rules are managed out-of-band by Lambda
  }
}

# EC2 instance role: SSM Session Manager access only. No open SSH port, no key pair.
resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}
