terraform {
  required_version = ">= 1.5.0"
}

locals {
  env_json_raw = file(var.env_json_path)

  # Attempt to decode JSON; errors will fail apply/plan
  env_json = jsondecode(local.env_json_raw)

  required_keys_present = alltrue([
    contains(keys(local.env_json), "environment_id"),
    contains(keys(local.env_json), "cluster_id"),
    contains(keys(local.env_json), "topics_config"),
  ])

  # Determine if topics_config is a list without requiring a specific element type
  topics_is_list = can(tolist(local.env_json.topics_config))

  # Phase 2 validations
  env_id_valid     = try(can(regex("^env-[A-Za-z0-9]+$", local.env_json.environment_id)), false)
  cluster_id_valid = try(can(regex("^lkc-[A-Za-z0-9]+$", local.env_json.cluster_id)), false)

  topics                = try(local.env_json.topics_config, [])
  topics_name_is_valid  = [for t in local.topics : can(regex("^[A-Za-z0-9._-]+$", try(t.name, "")))]
  topics_partitions_ok  = [for t in local.topics : try(tonumber(t.partitions), 0) >= 1]
  topics_rf_ok          = [for t in local.topics : try(tonumber(t.replication_factor), 0) >= 1]
  topics_config_is_map  = [for t in local.topics : can(tomap(try(t.config, {})))]
  topics_each_valid     = [for i in range(length(local.topics)) : local.topics_name_is_valid[i] && local.topics_partitions_ok[i] && local.topics_rf_ok[i] && local.topics_config_is_map[i]]
  topics_all_valid      = length(local.topics) == 0 ? false : alltrue(local.topics_each_valid)
  topics_count          = length(local.topics)
  topics_names          = [for t in local.topics : lower(try(t.name, "")) if try(t.name, "") != ""]
  topics_names_unique   = length(local.topics_names) == length(distinct(local.topics_names))
  topics_invalid_names  = [for t in local.topics : try(t.name, "") if !can(regex("^[A-Za-z0-9._-]+$", try(t.name, "")))]

  identities_structurally_valid = can(tolist(try(local.env_json.service_accounts, [])))
  rbac_structurally_valid       = can(tolist(try(local.env_json.rbac, [])))
  acls_structurally_valid       = can(tolist(try(local.env_json.acls, [])))
}

output "environment_id" {
  value       = try(local.env_json.environment_id, null)
  description = "Environment ID from config"
}

output "cluster_id" {
  value       = try(local.env_json.cluster_id, null)
  description = "Cluster ID from config"
}

output "required_keys_present" {
  value       = local.required_keys_present
  description = "Whether required top-level keys exist"
}

output "topics_is_list" {
  value       = local.topics_is_list
  description = "Whether topics_config is a list"
}

output "env_id_valid" {
  value       = local.env_id_valid
  description = "Environment ID matches expected pattern"
}

output "cluster_id_valid" {
  value       = local.cluster_id_valid
  description = "Cluster ID matches expected pattern"
}

output "topics_all_valid" {
  value       = local.topics_all_valid
  description = "All topics entries are structurally valid"
}

output "topics_count" {
  value       = local.topics_count
  description = "Number of topics configured"
}

output "topics_names_unique" {
  value       = local.topics_names_unique
  description = "Topic names are unique (case-insensitive)"
}

output "topics_invalid_names" {
  value       = local.topics_invalid_names
  description = "List of invalid topic names"
}

output "identities_structurally_valid" {
  value       = local.identities_structurally_valid
  description = "service_accounts array is a list"
}

output "rbac_structurally_valid" {
  value       = local.rbac_structurally_valid
  description = "rbac array is a list"
}

output "acls_structurally_valid" {
  value       = local.acls_structurally_valid
  description = "acls array is a list"
}
