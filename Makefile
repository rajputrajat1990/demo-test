SHELL := /bin/bash
.ONESHELL:

# Defaults
OFFICIAL_PROVIDER_REPO_URL ?= https://github.com/confluentinc/terraform-provider-confluent.git
ATTACH_MODE ?=

export ATTACH_MODE
export OFFICIAL_PROVIDER_REPO_URL

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: setup
setup:
	@chmod +x $(ROOT_DIR)/scripts/setup.sh
	@$(ROOT_DIR)/scripts/setup.sh

.PHONY: validate
validate:
	@chmod +x $(ROOT_DIR)/scripts/validate.sh
	@echo "  smoke-kafka-key       - Create key, grant RBAC, list topics, emit artifact"
	@$(ROOT_DIR)/scripts/validate.sh

.PHONY: ci-env-check

# One-shot: create key (REST), grant RBAC (REST), list topics and write artifact
.PHONY: smoke-kafka-key
smoke-kafka-key:
	@bash -lc 'set -euo pipefail; chmod +x scripts/smoke-kafka-key.sh; scripts/smoke-kafka-key.sh'

.PHONY: docker-smoke-kafka-key
docker-smoke-kafka-key: docker-build
	docker run --rm -e CONFLUENT_CLOUD_API_KEY -e CONFLUENT_CLOUD_API_SECRET -e SERVICE_ACCOUNT_ID \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/smoke-kafka-key.sh'
ci-env-check:
	@chmod +x $(ROOT_DIR)/scripts/ci-env-check.sh
	@$(ROOT_DIR)/scripts/ci-env-check.sh

.PHONY: docker-build
docker-build:
	docker build -t confluent-testing-framework:dev $(ROOT_DIR)

.PHONY: docker-setup
docker-setup: docker-build
	docker run --rm -e ATTACH_MODE -e OFFICIAL_PROVIDER_REPO_URL -e INTERNAL_FRAMEWORK_REPO_URL \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/setup.sh'

.PHONY: docker-validate
docker-validate: docker-build
	docker run --rm -e ATTACH_MODE -e OFFICIAL_PROVIDER_REPO_URL -e INTERNAL_FRAMEWORK_REPO_URL \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/validate.sh'

.PHONY: docker-ci-env-check
docker-ci-env-check: docker-build
	docker run --rm -e CONFLUENT_CLOUD_API_KEY -e CONFLUENT_CLOUD_API_SECRET \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/ci-env-check.sh'

.PHONY: confluent-check
confluent-check:
	@chmod +x $(ROOT_DIR)/scripts/confluent-check.sh
	@$(ROOT_DIR)/scripts/confluent-check.sh

.PHONY: sync-config
sync-config:
	@chmod +x $(ROOT_DIR)/scripts/sync-config.sh
	@$(ROOT_DIR)/scripts/sync-config.sh

.PHONY: docker-confluent-check
docker-confluent-check: docker-build
	docker run --rm -e CONFLUENT_CLOUD_API_KEY -e CONFLUENT_CLOUD_API_SECRET -e CONFLUENT_API_BASE \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/confluent-check.sh'

.PHONY: test-source
test-source:
	@chmod +x $(ROOT_DIR)/scripts/test-source.sh
	@$(ROOT_DIR)/scripts/test-source.sh

.PHONY: docker-test-source
docker-test-source: docker-build
	docker run --rm -e KAFKA_API_KEY -e KAFKA_API_SECRET -e CONFLUENT_KAFKA_API_KEY -e CONFLUENT_KAFKA_API_SECRET \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/test-source.sh'

.PHONY: test-flink
test-flink:
	@chmod +x $(ROOT_DIR)/scripts/test-flink.sh
	@$(ROOT_DIR)/scripts/test-flink.sh

.PHONY: docker-test-flink
docker-test-flink: docker-build
	docker run --rm -e KAFKA_API_KEY -e KAFKA_API_SECRET -e CONFLUENT_KAFKA_API_KEY -e CONFLUENT_KAFKA_API_SECRET \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/test-flink.sh'
.PHONY: docker-sync-config
docker-sync-config: docker-build
	docker run --rm -e CONFLUENT_CLOUD_API_KEY -e CONFLUENT_CLOUD_API_SECRET -e CONFLUENT_API_BASE \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/sync-config.sh'

.PHONY: generate-kafka-api-key
generate-kafka-api-key:
	@chmod +x $(ROOT_DIR)/scripts/generate-kafka-api-key.sh
	@$(ROOT_DIR)/scripts/generate-kafka-api-key.sh

.PHONY: docker-generate-kafka-api-key
docker-generate-kafka-api-key: docker-build
	docker run --rm -e CONFLUENT_CLOUD_API_KEY -e CONFLUENT_CLOUD_API_SECRET -e SERVICE_ACCOUNT_ID \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/generate-kafka-api-key.sh'

.PHONY: grant-kafka-read
grant-kafka-read:
	@chmod +x $(ROOT_DIR)/scripts/grant-kafka-read.sh
	@$(ROOT_DIR)/scripts/grant-kafka-read.sh

.PHONY: docker-grant-kafka-read
docker-grant-kafka-read: docker-build
	docker run --rm -e CONFLUENT_CLOUD_API_KEY -e CONFLUENT_CLOUD_API_SECRET -e SERVICE_ACCOUNT_ID \
	  -v $(ROOT_DIR):/work -w /work \
	  confluent-testing-framework:dev bash -lc 'scripts/grant-kafka-read.sh'
