run "environment_and_cluster" {
  command = plan

  assert {
    condition     = output.required_keys_present
    error_message = "environment_details.json missing required top-level keys"
  }

  assert {
    condition     = output.environment_id != null && length(output.environment_id) > 0
    error_message = "environment_id must be non-empty"
  }

  assert {
    condition     = output.cluster_id != null && length(output.cluster_id) > 0
    error_message = "cluster_id must be non-empty"
  }

  assert {
    condition     = output.env_id_valid
    error_message = "environment_id must match pattern env-xxxxx"
  }

  assert {
    condition     = output.cluster_id_valid
    error_message = "cluster_id must match pattern lkc-xxxxx"
  }
}

run "identities_rbac_acls" {
  command = plan

  assert {
    condition     = output.identities_structurally_valid
    error_message = "service_accounts must be a list (even if empty)"
  }

  assert {
    condition     = output.rbac_structurally_valid
    error_message = "rbac must be a list (even if empty)"
  }

  assert {
    condition     = output.acls_structurally_valid
    error_message = "acls must be a list (even if empty)"
  }
}

run "topics" {
  command = plan

  assert {
    condition     = output.topics_is_list
    error_message = "topics_config must be a list"
  }

  assert {
    condition     = output.topics_count >= 1
    error_message = "at least one topic must be defined"
  }

  assert {
    condition     = output.topics_names_unique
    error_message = "topic names must be unique (case-insensitive)"
  }

  assert {
    condition     = output.topics_all_valid
    error_message = "one or more topics invalid; see topics_invalid_names"
  }
}
