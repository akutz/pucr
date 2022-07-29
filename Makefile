# Ensure Make is run with bash shell as some syntax below is bash-specific
SHELL:=/usr/bin/env bash

.DEFAULT_GOAL:=help

DOCS_01 := ./docs/01-prereqs
DOCS_02 := ./docs/02-tasks-api
DOCS_03 := ./docs/03-versions
DOCS_04 := ./docs/04-conversion-webhook

KIND_CLUSTER := how-crd-versions-work
KIND_CLUSTER := kind-$(KIND_CLUSTER)
KUBECTL := kubectl --context $(KIND_CLUSTER)

API_V1ALPHA1 := $(DOCS_02)/tasks-v1alpha1-crd.yaml
API_V1ALPHA1_AND_V1ALPHA2 := $(DOCS_03)/tasks-v1alpha1-and-v1alpha2-crd.yaml
API_V1ALPHA1_AND_V1ALPHA2_WITH_CONVERSION_WEBHOOK := $(DOCS_04)/tasks-v1alpha1-and-v1alpha2-crd-with-conversion-webhook.yaml

RES_NAME := my-task
RES_V1ALPHA1 := $(DOCS_02)/tasks-v1alpha1-resource.yaml
RES_V1ALPHA2 := $(DOCS_03)/tasks-v1alpha2-resource.yaml

CONVERSION_WEBHOOK_SERVER_SRC := $(DOCS_04)/main.go
CONVERSION_WEBHOOK_SERVER_CRT := $(DOCS_04)/server.crt
CONVERSION_WEBHOOK_SERVER_KEY := $(DOCS_04)/server.key
CONVERSION_WEBHOOK_SERVER_IMG_NAME := tasks-conversion-webhook-server

help:  # Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[0-9A-Za-z_-]+:.*?##/ { printf "  \033[36m%-45s\033[0m %s\n", $$1, $$2 } /^\$$\([0-9A-Za-z_-]+\):.*?##/ { gsub("_","-", $$1); printf "  \033[36m%-45s\033[0m %s\n", tolower(substr($$1, 3, length($$1)-7)), $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

## --------------------------------------
## Kind
## --------------------------------------

##@ kind:

.PHONY: kind-up
kind-up: ## Create a new kind cluster
	kind create cluster --name $(KIND_CLUSTER)

.PHONY: kind-down
kind-down: ## Delete the kind cluster
	kind delete cluster --name $(KIND_CLUSTER)

.PHONY: kind-2-curl
kind-2-curl: ## Saves the credentials & endpoint info for the kind cluster
# Write the client certificate's public key to 'client.crt'
	$(KUBECTL) config view --raw \
	  -ojsonpath='{.users[?(@.name == "$(KIND_CLUSTER)")].user.client-certificate-data}' | \
	  { base64 -d 2>/dev/null || base64 -D; } >client.crt

# Write the client certificate's private key to 'client.key'
	$(KUBECTL) config view --raw \
	  -ojsonpath='{.users[?(@.name == "$(KIND_CLUSTER)")].user.client-key-data}' | \
	  { base64 -d 2>/dev/null || base64 -D; } >client.key

# Write the certificate authority chain to `ca.crt`
	$(KUBECTL) config view --raw \
	  -o jsonpath='{.clusters[?(@.name == "$(KIND_CLUSTER)")].cluster.certificate-authority-data}' | \
	  { base64 -d 2>/dev/null || base64 -D; } >ca.crt

# Write the API server's URL to `url.txt`
	$(KUBECTL) config view --raw \
	  -o jsonpath='{.clusters[?(@.name == "$(KIND_CLUSTER)")].cluster.server}' \
	  >url.txt


## --------------------------------------
## APIs
## --------------------------------------

##@ apis:

.PHONY: apis-install-v1alpha1
apis-install-v1alpha1: ## Install the v1alpha1 tasks API
	$(KUBECTL) apply -f $(API_V1ALPHA1)

.PHONY: apis-install-v1alpha2
apis-install-v1alpha2: ## Install the v1alpha1 and v1alpha2 tasks APIs
	$(KUBECTL) apply -f $(API_V1ALPHA1_AND_V1ALPHA2)

.PHONY: apis-uninstall
apis-uninstall: ## Uninstall the APIs
	$(KUBECTL) delete customresourcedefinition.apiextensions.k8s.io/tasks.vmware.com


## --------------------------------------
## Resources
## --------------------------------------

##@ resources:

.PHONY: task-apply-v1alpha1-resource
task-apply-v1alpha1-resource: ## Apply a task resource at v1alpha1
	$(KUBECTL) apply -f $(RES_V1ALPHA1)

.PHONY: task-apply-v1alpha2-resource
task-apply-v1alpha2-resource: ## Apply a task resource at v1alpha2
	$(KUBECTL) apply -f $(RES_V1ALPHA2)

.PHONY: task-update-v1alpha1-resource
task-update-v1alpha1-resource: ## Update a resource at v1alpha1
	@make --quiet kind-2-curl
	curl  \
	  --cacert ca.crt \
	  --cert client.crt \
	  --key client.key \
	  --silent \
	  --show-error \
	  -H 'Accept: application/json' \
	  "$$(cat url.txt)/apis/vmware.com/v1alpha1/namespaces/default/tasks/my-task" | \
	jq '.spec.id="v1a1-my-updated-id"' | \
	curl  --cacert ca.crt \
	  --cert client.crt \
	  --key client.key \
	  --silent \
	  --show-error \
	  -X PUT \
	  -w'\n' \
	  -d @- \
	  -H 'Accept: application/json' \
	  -H 'Content-Type: application/json' \
	  "$$(cat url.txt)/apis/vmware.com/v1alpha1/namespaces/default/tasks/my-task" | \
	jq .

.PHONY: task-update-v1alpha2-resource
task-update-v1alpha2-resource: ## Update a resource at v1alpha2
	@make --quiet kind-2-curl
	curl  \
	  --cacert ca.crt \
	  --cert client.crt \
	  --key client.key \
	  --silent \
	  --show-error \
	  -H 'Accept: application/json' \
	  "$$(cat url.txt)/apis/vmware.com/v1alpha2/namespaces/default/tasks/my-task" | \
	jq '.spec.id="v1a2-my-updated-id"' | \
	jq '.spec.name="v1a2-my-updated-optional-name"' | \
	jq '.spec.operationID="v1a2-my-updated-required-op-id"' | \
	curl  --cacert ca.crt \
	  --cert client.crt \
	  --key client.key \
	  --silent \
	  --show-error \
	  -X PUT \
	  -w'\n' \
	  -d @- \
	  -H 'Accept: application/json' \
	  -H 'Content-Type: application/json' \
	  "$$(cat url.txt)/apis/vmware.com/v1alpha2/namespaces/default/tasks/my-task" | \
	jq .

.PHONY: task-patch-v1alpha1-resource
task-patch-v1alpha1-resource: ## Patch a resource at v1alpha1
	@make --quiet kind-2-curl
	curl  \
	  --cacert ca.crt \
	  --cert client.crt \
	  --key client.key \
	  --silent \
	  --show-error \
	  --request PATCH \
	  -H 'Content-Type: application/json-patch+json' \
	  -d '[{"op": "replace", "path": "/spec/id", "value": "v1a1-my-patched-id"}]' \
	  "$$(cat url.txt)/apis/vmware.com/v1alpha1/namespaces/default/tasks/my-task" | \
	jq .

.PHONY: task-get-v1alpha1-resource
task-get-v1alpha1-resource: ## Get a task resource at v1alpha1
	$(KUBECTL) get tasks.v1alpha1.vmware.com/$(RES_NAME) -oyaml

.PHONY: task-get-v1alpha2-resource
task-get-v1alpha2-resource: ## Get a task resource at v1alpha2
	$(KUBECTL) get tasks.v1alpha2.vmware.com/$(RES_NAME) -oyaml

.PHONY: task-delete-resource
task-delete-resource: ## Delete task resource
	$(KUBECTL) delete task $(RES_NAME)


## --------------------------------------
## Conversion Webhook Server
## --------------------------------------

##@ conversion-webhook-server:

.PHONY: server-start
server-start: ## Start the conversion webhook server
	cd $(dir $(CONVERSION_WEBHOOK_SERVER_SRC)) && \
	  go run $(notdir $(CONVERSION_WEBHOOK_SERVER_SRC))

.PHONY: server-gen-certs
server-gen-certs: ## Generate a new SSL key pair for the webhook server
	openssl req -x509 \
	  -sha256 -days 3650 \
	  -nodes \
	  -newkey rsa:2048 \
	  -subj "/CN=tasks-conversion-webhook-server.default.svc.cluster.local/C=US/L=Palo Alto" \
	  -addext basicConstraints=critical,CA:TRUE \
	  -addext "certificatePolicies = 1.2.3.4" \
	  -addext keyUsage="digitalSignature,keyEncipherment,cRLSign,keyCertSign" \
	  -addext extendedKeyUsage="serverAuth,clientAuth" \
	  -addext "subjectAltName = DNS:tasks-conversion-webhook-server.default.svc,DNS:tasks-conversion-webhook-server.default.svc.cluster.local" \
	  -keyout $(DOCS_04)/server.key -out $(DOCS_04)/server.crt

.PHONY: server-build-image
server-build-image: ## Build the container image for the webhook server
	docker build -f $(DOCS_04)/Dockerfile -t $(CONVERSION_WEBHOOK_SERVER_IMG_NAME) $(DOCS_04)

.PHONY: server-load-image
server-load-image: server-build-image
server-load-image: ## Load the conversion webhook server image
	kind load docker-image --name $(KIND_CLUSTER) $(CONVERSION_WEBHOOK_SERVER_IMG_NAME)

.PHONY: server-install-pod-and-service
server-install-pod-and-service: ## Install the conversion webhook server pod and service
	sed -e 's/SERVER_CRT/'"$$(base64 "$(CONVERSION_WEBHOOK_SERVER_CRT)")"'/' \
	    -e 's/SERVER_KEY/'"$$(base64 "$(CONVERSION_WEBHOOK_SERVER_KEY)")"'/' \
	  "$(DOCS_04)/conversion-webhook-server.yaml" | \
	$(KUBECTL) apply -f -

.PHONY: server-uninstall-pod-and-service
server-uninstall-pod-and-service: ## Uninstall the conversion webhook server pod and service
	$(KUBECTL) delete -f $(DOCS_04)/conversion-webhook-server.yaml

.PHONY: server-install-crd-webhook
server-install-crd-webhook: ## Install the update to the task API to use the conversion webhook
	sed -e 's/CA_BUNDLE_BASE_64/'"$$(base64 "$(CONVERSION_WEBHOOK_SERVER_CRT)")"'/' \
	  "$(API_V1ALPHA1_AND_V1ALPHA2_WITH_CONVERSION_WEBHOOK)" | \
	$(KUBECTL) apply -f -

.PHONY: server-install
server-install: server-load-image server-install-pod-and-service server-install-crd-webhook
server-install: ## Install the conversion webhook server

.PHONY: server-reinstall
server-reinstall: server-uninstall-pod-and-service server-install
server-reinstall: ## Reinstall the conversion webhook server

