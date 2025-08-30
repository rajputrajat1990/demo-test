terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = ">= 2.0.0"
    }
  }
}

resource "confluent_role_binding" "rb" {
  principal   = var.principal
  role_name   = var.role_name
  crn_pattern = var.crn_pattern
}

output "role_binding_id" {
  value     = confluent_role_binding.rb.id
  sensitive = false
}