variable "environment_id" {
  description = "Confluent Cloud environment ID (env-xxxxx)"
  type        = string
}

variable "kafka_cluster_id" {
  description = "Kafka cluster ID (lkc-xxxxx)"
  type        = string
}

variable "owner_service_account_id" {
  description = "Service Account ID to own the API key (sa-xxxxx)"
  type        = string
}

variable "display_name" {
  description = "Display name for the API key"
  type        = string
  default     = "generated-by-terraform"
}

variable "description" {
  description = "Description for the API key"
  type        = string
  default     = "Generated via Terraform keygen module"
}

// no-op
