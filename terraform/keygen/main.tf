terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = ">= 2.0.0"
    }
  }
}

resource "confluent_api_key" "kafka_key" {
  display_name = var.display_name
  description  = var.description

  owner {
    id          = var.owner_service_account_id
    api_version = "iam/v2"
    kind        = "ServiceAccount"
  }

  managed_resource {
    id          = var.kafka_cluster_id
    api_version = "cmk/v2"
    kind        = "Cluster"
    environment {
      id = var.environment_id
    }
  }

}

output "api_key" {
  description = "The generated Kafka API key"
  value       = confluent_api_key.kafka_key.id
  sensitive   = true
}

output "api_secret" {
  description = "The generated Kafka API secret"
  value       = confluent_api_key.kafka_key.secret
  sensitive   = true
}
