variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository for OIDC authentication (e.g. username/Recovery-Engine-AWS)"
  type        = string
  default     = "example-user/Recovery-Engine-AWS"
}

variable "tags" {
  description = "Tags to attach to IAM resources"
  type        = map(string)
  default     = {}
}
