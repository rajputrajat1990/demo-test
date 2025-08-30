# Confluent Testing Framework — Phase 1 (Setup)

This repository implements Phase 1 of the plan: setup with an attach-mode prompt, repo cloning, logging initialization, and per-run `test_session_id` to tag artifacts and logs.

## What’s included

- `scripts/setup.sh` — main setup workflow
- `scripts/utils/logging.sh` — JSONL logging with `TEST_SESSION_ID`
- `configs/environment_details.json` — example config used when attaching to an existing environment
- `artifacts/` — logs and per-session folders (created on demand)
- `Dockerfile` and `Makefile` — optional containerized/local entry points

## Quick start (local)

Interactive prompt (attach existing vs. official modules):

```bash
make setup
make validate   # Phase 2 scaffold: will skip if no terraform/
make smoke-kafka-key  # One-shot: create key (REST), grant RBAC, list topics, emit artifact
```

Non-interactive (CI-friendly):

```bash
ATTACH_MODE=existing_env make setup
# or
ATTACH_MODE=official_modules OFFICIAL_PROVIDER_REPO_URL=https://github.com/confluentinc/terraform-provider-confluent.git make setup
```

Outputs:

- Logs at `artifacts/logs/run-<TEST_SESSION_ID>.log` (JSON lines)
- Session folder at `artifacts/sessions/<TEST_SESSION_ID>/` with context snapshot
	- `smoke_kafka_key.json` — summary from the one-shot Kafka key smoke (non-blocking)

## Run in Docker (optional)

```bash
make docker-build
ATTACH_MODE=existing_env make docker-setup
make docker-validate # runs the validation scaffold in container
make docker-smoke-kafka-key # run the smoke workflow in container
make confluent-check # REST connectivity check (requires env vars)
```

Environment variables you can set:

- `ATTACH_MODE` — `existing_env` | `official_modules`
- `OFFICIAL_PROVIDER_REPO_URL` — defaults to Confluent Terraform Provider repo
- `INTERNAL_FRAMEWORK_REPO_URL` — optional, clone your internal framework

Notes:

- `setup.sh` validates `configs/environment_details.json` when using `existing_env`.
- No infrastructure is created in Phase 1; this only prepares local state, logs, and (optionally) clones repos.
- `confluent-check.sh` performs a safe Confluent Cloud REST probe and writes `artifacts/sessions/<TEST_SESSION_ID>/confluent_api_check.json`. Set:
	- `CONFLUENT_CLOUD_API_KEY` and `CONFLUENT_CLOUD_API_SECRET`
	- Optional: `CONFLUENT_API_BASE` (defaults to `https://api.confluent.cloud`)

Smoke requirements:
- `CONFLUENT_CLOUD_API_KEY`/`CONFLUENT_CLOUD_API_SECRET` — org admin or suitable privileges
- `SERVICE_ACCOUNT_ID` — target service account to own the Kafka API key and receive DeveloperRead on the cluster
- `configs/environment_details.json` — must include `environment_id`, `cluster_id`, and `http_endpoint`
