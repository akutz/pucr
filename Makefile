# Ensure Make is run with bash shell as some syntax below is bash-specific
SHELL:=/usr/bin/env bash

.DEFAULT_GOAL:=help

MAKEQ := $(MAKE) --silent --no-print-directory

PROJECT_NAME := pucr

KUBE_CA_CRT        := .kube/server-ca.crt
KUBE_CLIENT_CRT    := .kube/client.crt
KUBE_CLIENT_KEY    := .kube/client.key
KUBE_URL_TXT       := .kube/url.txt
KUBE_URL_DIND_TXT  := .kube/url-dind.txt

KIND_CLUSTER       := $(PROJECT_NAME)
KUBE_CONTEXT       := kind-$(KIND_CLUSTER)
KUBE_CONTEXT_DIND  := $(KUBE_CONTEXT)-dind

ifeq (1,$(DOCKER_IN_DOCKER))
ACTIVE_KUBE_CONTEXT := $(KUBE_CONTEXT_DIND)
ACTIVE_KUBE_URL_TXT := $(KUBE_URL_DIND_TXT)
else
ACTIVE_KUBE_CONTEXT := $(KUBE_CONTEXT)
ACTIVE_KUBE_URL_TXT := $(KUBE_URL_TXT)
endif

KUBECTL := kubectl --context $(ACTIVE_KUBE_CONTEXT)

CURL := curl --cacert $(KUBE_CA_CRT) --cert $(KUBE_CLIENT_CRT) --key $(KUBE_CLIENT_KEY)
CURL := $(CURL) --silent --show-error
CURL := $(CURL) -H 'Accept: application/json'
CURL_H_JSON  := -H 'Content-Type: application/json'
CURL_H_JSONP := -H 'Content-Type: application/json-patch+json'
CURL_GET    := $(CURL) -XGET    $(CURL_H_JSON) -w'\n'
CURL_PUT    := $(CURL) -XPUT    $(CURL_H_JSON)
CURL_POST   := $(CURL) -XPOST   $(CURL_H_JSON)
CURL_PATCH  := $(CURL) -XPATCH  $(CURL_H_JSONP)
CURL_DELETE := $(CURL) -XDELETE $(CURL_H_JSONP)

API := api.yaml
API_WEBHOOK_PATCH := api-webhook-patch.yaml

RES_NAME := my-task
RES_V1ALPHA1 := resource-v1alpha1.yaml
RES_V1ALPHA2 := resource-v1alpha2.yaml
RES_V1ALPHA1_URL := apis/akutz.github.org/v1alpha1/namespaces/default/tasks/$(RES_NAME)
RES_V1ALPHA2_URL := apis/akutz.github.org/v1alpha2/namespaces/default/tasks/$(RES_NAME)
RES_V1ALPHA1_PATCH := [{"op": "replace", "path": "/spec/id", "value": "v1a1-my-patched-id"}]
RES_V1ALPHA2_PATCH := [{"op": "replace", "path": "/spec/id", "value": "v1a2-my-patched-id"}]

SERVER_DNS := tasks-conversion-webhook
SERVER_SRC := server.go
SERVER_BIN := server
SERVER_TAG := server
SERVER_YML := server.yaml
SERVER_CRT := .webhook/server.crt
SERVER_KEY := .webhook/server.key

IMG_NAME := akutz/$(PROJECT_NAME)
IMG_PLAT ?= linux/amd64,linux/arm64

help:  # Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[0-9A-Za-z_-]+:.*?##/ { printf "  \033[36m%-45s\033[0m %s\n", $$1, $$2 } /^\$$\([0-9A-Za-z_-]+\):.*?##/ { gsub("_","-", $$1); printf "  \033[36m%-45s\033[0m %s\n", tolower(substr($$1, 3, length($$1)-7)), $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

## --------------------------------------
## Kind
## --------------------------------------

##@ kind:

.PHONY: kind-up
kind-up: ## Create a new kind cluster
	kind create cluster --name $(KIND_CLUSTER)
	@$(MAKEQ) kind-dind-context
	@$(MAKEQ) kind-2-curl

.PHONY: kind-down
kind-down: ## Delete the kind cluster
	kind delete cluster --name $(KIND_CLUSTER)
	@$(KUBECTL) config delete-cluster $(KUBE_CONTEXT_DIND)
	@$(KUBECTL) config delete-context $(KUBE_CONTEXT_DIND)
	@rm -f $(KUBE_CA_CRT) $(KUBE_CLIENT_CRT) $(KUBE_CLIENT_KEY) $(KUBE_URL_TXT) $(KUBE_URL_DIND_TXT)

.PHONY: kind-dind-context
kind-dind-context:
	@$(KUBECTL) config set-cluster $(KUBE_CONTEXT_DIND) --server="https://$$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(KIND_CLUSTER)-control-plane):6443" --insecure-skip-tls-verify=true
	@$(KUBECTL) config set-context $(KUBE_CONTEXT_DIND) --cluster=$(KUBE_CONTEXT_DIND) --user=$(KUBE_CONTEXT)

.PHONY: $(KUBE_CA_CRT)
$(KUBE_CA_CRT):
	@mkdir -p $(@D)
	$(KUBECTL) config view --raw \
	  -o jsonpath='{.clusters[?(@.name == "kind-$(KIND_CLUSTER)")].cluster.certificate-authority-data}' | \
	  { base64 -d 2>/dev/null || base64 -D; } \
	  >$@

.PHONY: $(KUBE_CLIENT_CRT)
$(KUBE_CLIENT_CRT):
	@mkdir -p $(@D)
	$(KUBECTL) config view --raw \
	  -ojsonpath='{.users[?(@.name == "kind-$(KIND_CLUSTER)")].user.client-certificate-data}' | \
	  { base64 -d 2>/dev/null || base64 -D; } \
	  >$@

.PHONY: $(KUBE_CLIENT_KEY)
$(KUBE_CLIENT_KEY):
	@mkdir -p $(@D)
	$(KUBECTL) config view --raw \
	  -ojsonpath='{.users[?(@.name == "kind-$(KIND_CLUSTER)")].user.client-key-data}' | \
	  { base64 -d 2>/dev/null || base64 -D; } \
	  >$@

.PHONY: $(KUBE_URL_TXT)
$(KUBE_URL_TXT):
	@mkdir -p $(@D)
	$(KUBECTL) config view --raw \
	  -o jsonpath='{.clusters[?(@.name == "kind-$(KIND_CLUSTER)")].cluster.server}' \
	  >$@

.PHONY: $(KUBE_URL_DIND_TXT)
$(KUBE_URL_DIND_TXT):
	@mkdir -p $(@D)
	$(KUBECTL) config view --raw \
	  -o jsonpath='{.clusters[?(@.name == "$(KUBE_CONTEXT_DIND)")].cluster.server}' \
	  >$@

.PHONY: kind-2-curl
kind-2-curl: $(KUBE_CA_CRT) $(KUBE_CLIENT_CRT) $(KUBE_CLIENT_KEY) $(KUBE_URL_TXT) $(KUBE_URL_DIND_TXT)


## --------------------------------------
## Image
## --------------------------------------

##@ docker image:

.PHONY: image-build
image-build: ## Build the docker image
	docker build -t $(IMG_NAME) .

.PHONY: image-build-all
image-build-all: ## Build the container image for multiple platforms
	docker buildx build --platform $(IMG_PLAT) -t $(IMG_NAME) .

.PHONY: image-load
image-load: image-build
image-load:
	kind load docker-image --name $(KIND_CLUSTER) $(IMG_NAME)

.PHONY: image-push
image-push: ## Push the docker image
	docker push $(IMG_NAME)

.PHONY: image-push-all
image-push-all: PUSH_ALL=--push
image-push-all: image-build-all
image-push-all: ## Push the docker image for multiple platforms

.PHONY: image-run
image-run: ## Run the docker image
	@mkdir -p "$(HOME)/.kube"
	docker run \
	  -it --rm \
	  --privileged \
	  --network kind \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  -v "$(HOME)/.kube":/root/.kube \
	  -v "$(CURDIR)/.kube":/$(PROJECT_NAME)/.kube \
	  $(IMG_NAME)


## --------------------------------------
## APIs
## --------------------------------------

##@ api:

.PHONY: api-install
api-install: ## Install the tasks API
	$(KUBECTL) apply -f $(API)

.PHONY: api-with-webhook
api-with-webhook:
	yq '.spec = .spec * load("$(API_WEBHOOK_PATCH)").spec | with(.spec.conversion.webhook.clientConfig; .caBundle = (load_str("$(SERVER_CRT)") | @base64))' $(API)

.PHONY: api-install-with-webhook
api-install-with-webhook: ## Install the tasks API with a conversion webhook
	$(MAKEQ) api-with-webhook | $(KUBECTL) apply -f -

.PHONY: api-uninstall
api-uninstall: ## Uninstall the tasks API
	$(KUBECTL) delete -f $(API)


## --------------------------------------
## Resources
## --------------------------------------

##@ resource operations with kubectl:

.PHONY: kubectl-get-v1a1
kubectl-get-v1a1: ## Get task resource at v1alpha1
	$(KUBECTL) get tasks.v1alpha1.akutz.github.org/$(RES_NAME) -oyaml

.PHONY: kubectl-get-v1a2
kubectl-get-v1a2: ## Get task resource at v1alpha2
	$(KUBECTL) get tasks.v1alpha2.akutz.github.org/$(RES_NAME) -oyaml

.PHONY: kubectl-apply-v1a1
kubectl-apply-v1a1: ## Apply task resource at v1alpha1
	$(KUBECTL) apply -f $(RES_V1ALPHA1) $(KUBECTL_FLAGS)

.PHONY: kubectl-apply-v1a2
kubectl-apply-v1a2: ## Apply task resource at v1alpha2
	$(KUBECTL) apply -f $(RES_V1ALPHA2) $(KUBECTL_FLAGS)

.PHONY: kubectl-apply-v1a1-w-ssa
kubectl-apply-v1a1-w-ssa: KUBECTL_FLAGS=--server-side=true
kubectl-apply-v1a1-w-ssa: res-apply-v1a1
kubectl-apply-v1a1-w-ssa: ## Apply task resource at v1alpha1 with server-side apply

.PHONY: kubectl-apply-v1a2-w-ssa
kubectl-apply-v1a2-w-ssa: KUBECTL_FLAGS=--server-side=true
kubectl-apply-v1a2-w-ssa: res-apply-v1a2
kubectl-apply-v1a2-w-ssa: ## Apply task resource at v1alpha2 with server-side apply

.PHONY: kubectl-delete
kubectl-delete: ## Delete task resource
	$(KUBECTL) delete task $(RES_NAME)


##@ resource operations with curl:

.PHONY: curl-get-v1a1
curl-get-v1a1: ## Get task resource at v1alpha1
	$(CURL_GET) "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA1_URL)" | yq -Poyaml

.PHONY: curl-get-v1a2
curl-get-v1a2: ## Get task resource at v1alpha2
	$(CURL_GET) "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA2_URL)" | yq -Poyaml

.PHONY: curl-create-v1a1
curl-create-v1a1: ## Create task resource at v1alpha1
	yq $(RES_V1ALPHA1) -ojson | \
	$(CURL_POST) -d @- "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA1_URL)" | \
	yq -Poyaml

.PHONY: curl-create-v1a2
curl-create-v1a2: ## Create task resource at v1alpha2
	yq $(RES_V1ALPHA2) -ojson | \
	$(CURL_POST) -d @- "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA2_URL)" | \
	yq -Poyaml

.PHONY: curl-update-v1a1
curl-update-v1a1: ## Update resource at v1alpha1
	$(CURL_GET) "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA1_URL)" | \
	jq '.spec.id="v1a1-my-updated-id"' | \
	$(CURL_PUT) -d @- "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA1_URL)" | \
	yq -Poyaml

.PHONY: curl-update-v1a2
curl-update-v1a2: ## Update resource at v1alpha2
	$(CURL_GET) "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA2_URL)" | \
	jq '.spec.id="v1a2-my-updated-id"' | \
	$(CURL_PUT) -d @- "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA2_URL)" | \
	yq -Poyaml

.PHONY: curl-patch-v1a1
curl-patch-v1a1: ## Patch resource at v1alpha1
	$(CURL_PATCH) -d '$(RES_V1ALPHA1_PATCH)' "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA1_URL)" | \
	yq -Poyaml

.PHONY: curl-patch-v1a2
curl-patch-v1a2: ## Patch resource at v1alpha2
	$(CURL_PATCH) -d '$(RES_V1ALPHA2_PATCH)' "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA2_URL)" | \
	yq -Poyaml

.PHONY: curl-delete-v1a1
curl-delete-v1a1: ## Delete task resource at v1alpha1
	$(CURL_DELETE) "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA1_URL)" | yq -Poyaml

.PHONY: curl-delete-v1a2
curl-delete-v1a2: ## Delete task resource at v1alpha2
	$(CURL_DELETE) "$(file <$(ACTIVE_KUBE_URL_TXT))/$(RES_V1ALPHA2_URL)" | yq -Poyaml


## --------------------------------------
## Server
## --------------------------------------

##@ conversion webhook server:

.PHONY: server-tls
server-tls:
	@mkdir -p $(dir $(SERVER_CRT))
	openssl req -x509 \
	  -sha256 -days 3650 \
	  -nodes \
	  -newkey rsa:2048 \
	  -subj "/CN=$(SERVER_DNS).default.svc.cluster.local/C=US/L=Austin" \
	  -addext basicConstraints=critical,CA:TRUE \
	  -addext "certificatePolicies = 1.2.3.4" \
	  -addext keyUsage="digitalSignature,keyEncipherment,cRLSign,keyCertSign" \
	  -addext extendedKeyUsage="serverAuth,clientAuth" \
	  -addext "subjectAltName = DNS:$(SERVER_DNS).default.svc,DNS:$(SERVER_DNS).default.svc.cluster.local" \
	  -keyout $(SERVER_KEY) -out $(SERVER_CRT)

$(SERVER_BIN): $(SERVER_SRC)
	go build -v --tags $(SERVER_TAG) -o $@

.PHONY: server-print-pod-and-service
server-print-pod-and-service:
	yq 'with(select(.kind == "Secret").data; .crt = (load_str("$(SERVER_CRT)") | @base64) | .key = (load_str("$(SERVER_KEY)") | @base64))' $(SERVER_YML)

.PHONY: server-install-pod-and-service
server-install-pod-and-service:
	$(MAKEQ) server-print-pod-and-service | $(KUBECTL) apply -f -

.PHONY: server-uninstall-pod-and-service
server-uninstall-pod-and-service:
	$(KUBECTL) delete -f $(SERVER_YML)

.PHONY: server-install
server-install: image-load server-install-pod-and-service
server-install: ## Install the conversion webhook server

.PHONY: server-uninstall
server-uninstall: ## Uninstall the conversion webhook server
	$(KUBECTL) delete -f $(SERVER_YML)

.PHONY: server-restart
server-restart: ## Restart the conversion webhook server
	$(MAKEQ) server-uninstall
	$(MAKEQ) server-install
