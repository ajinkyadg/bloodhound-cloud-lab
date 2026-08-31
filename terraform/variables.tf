variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to tag/prefix every resource, and to scope the account-safety verify script."
  type        = string
  default     = "crte-bloodhound"
}

variable "admin_email" {
  description = "Your email. Used as the Cognito login username and the AWS Budget alert recipient."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type running BloodHound CE. t3.medium (4GB) is enough for most CRTE-scale AD environments; bump to t3.large for bigger ingests."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size (OS + docker images)."
  type        = number
  default     = 20
}

variable "data_volume_size_gb" {
  description = "Second EBS volume size for Neo4j + Postgres data. This is what survives stop/start."
  type        = number
  default     = 20
}

variable "bloodhound_port" {
  description = "HTTPS port BloodHound's UI is exposed on (behind the Caddy TLS sidecar)."
  type        = number
  default     = 8443
}

variable "idle_timeout_minutes" {
  description = "Minutes without a heartbeat from the landing page before the instance is auto-stopped and access revoked."
  type        = number
  default     = 20
}

variable "monthly_budget_usd" {
  description = "AWS Budget monthly cap in USD. You'll get email alerts at 50/80/100% of this."
  type        = number
  default     = 20
}
