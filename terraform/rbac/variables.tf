variable "principal" {
  description = "Principal to bind role to, e.g., User:sa-xxxxx"
  type        = string
}

variable "role_name" {
  description = "RBAC role name to grant (e.g., DeveloperRead, DeveloperManage)"
  type        = string
  default     = "DeveloperRead"
}

variable "crn_pattern" {
  description = "CRN pattern of the Kafka resource (kafka cluster or topic)"
  type        = string
}