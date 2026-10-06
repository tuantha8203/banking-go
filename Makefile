# banking-go — developer entry points. `make help` lists targets.
# make test / make lint never need Docker; integration tests (testcontainers) run with `make test-integration`.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

GO_MODULES := pkg services/core services/public-api services/admin-api services/mocks
GO_PKGS    := $(foreach m,$(GO_MODULES),./$(m)/...)
OPENAPI_SERVICES := public-api admin-api

PNPM    := npx -y pnpm@12.9.1
BIN     := $(CURDIR)/bin
# Tools (buf, sqlc, goose, protoc-gen-go, protoc-gen-go-grpc) are pinned by `tool` directives in
# tools/go.mod, a module kept outside go.work so its dependencies never leak into the services.
GOTOOL  := cd $(CURDIR)/tools && GOWORK=off go tool
COMPOSE := docker compose -f deploy/compose/compose.yaml

.PHONY: help
help: ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------------------------
.PHONY: install
install: ## Download Go modules and install pnpm deps (frozen lockfile)
	@for m in $(GO_MODULES); do (cd $$m && go mod download); done
	cd tools && GOWORK=off go mod download
	$(PNPM) install --frozen-lockfile

TOOL_STAMP := $(BIN)/.tools-stamp
$(TOOL_STAMP): tools/go.mod tools/go.sum
	cd tools && GOWORK=off go build -o $(BIN)/ \
		github.com/bufbuild/buf/cmd/buf \
		github.com/sqlc-dev/sqlc/cmd/sqlc \
		github.com/pressly/goose/v3/cmd/goose \
		google.golang.org/protobuf/cmd/protoc-gen-go \
		google.golang.org/grpc/cmd/protoc-gen-go-grpc \
		sigs.k8s.io/kind \
		github.com/yannh/kubeconform/cmd/kubeconform \
		github.com/mikefarah/yq/v4
	@touch $@

.PHONY: tools
tools: $(TOOL_STAMP) ## Build pinned Go tools into ./bin

# k8s/devops CLIs (platform v1): Go tools above + checksum-verified downloads (tools/k8s-tools.lock).
KIND        := $(BIN)/kind
KUBECTL     := $(BIN)/kubectl
HELM        := $(BIN)/helm
KUBECONFORM := $(BIN)/kubeconform
YQ          := $(BIN)/yq
PROMTOOL    := $(BIN)/promtool
AMTOOL      := $(BIN)/amtool
KUBESEAL    := $(BIN)/kubeseal
ACTIONLINT  := $(BIN)/actionlint
COSIGN      := $(BIN)/cosign
GH          := $(BIN)/gh
export HELM_PLUGINS := $(BIN)/helm-plugins

K8S_TOOLS_STAMP := $(BIN)/.k8s-tools-stamp
$(K8S_TOOLS_STAMP): tools/k8s-tools.lock scripts/install-k8s-tools.sh
	scripts/install-k8s-tools.sh $(BIN)
	@touch $@

.PHONY: tools-k8s
tools-k8s: $(TOOL_STAMP) $(K8S_TOOLS_STAMP) ## Pinned kind/kubectl/helm(+unittest)/kubeconform/yq/promtool/amtool/kubeseal/actionlint/cosign/gh in ./bin

# ---------------------------------------------------------------------------------------------
.PHONY: build build-go build-web
build: build-go build-web ## Build all Go modules and SPAs
build-go:
	go build $(GO_PKGS)
build-web:
	$(PNPM) -r build

.PHONY: test test-go test-web
test: test-go test-web ## Unit tests: Go (all modules) + web (vitest); no Docker
test-go:
	go test $(GO_PKGS)
test-web:
	$(PNPM) -r test

.PHONY: test-one
test-one: ## One test. Go: make test-one PKG=./pkg/health RUN=TestReadyz · Web: make test-one WEB=@banking-go/web-customer RUN="renders"
ifdef PKG
	go test -count=1 -v $(PKG) $(if $(RUN),-run '$(RUN)')
else ifdef WEB
	$(PNPM) --filter $(WEB) exec vitest run $(if $(RUN),-t "$(RUN)")
else
	@echo "usage:"
	@echo "  make test-one PKG=./pkg/health RUN=TestReadyz                   # Go package, optional -run regex"
	@echo "  make test-one PKG=./services/core/cmd/core                      # all tests of one Go package"
	@echo "  make test-one WEB=@banking-go/web-customer RUN='renders'        # vitest in one workspace package, -t filter"
	@echo "  make test-one WEB=@banking-go/theme                             # all vitest tests of one package"
endif

.PHONY: test-integration
test-integration: ## Integration tests (build tag integration, testcontainers; needs Docker). No such tests yet.
	go test -tags integration -count=1 $(GO_PKGS)

.PHONY: e2e
e2e: ## Playwright smoke e2e against `vite preview` (run once: $(PNPM) --filter @banking-go/web-customer exec playwright install chromium)
	$(PNPM) -r build
	$(PNPM) -r e2e

# ---------------------------------------------------------------------------------------------
.PHONY: lint lint-go lint-proto lint-web vet
lint: lint-go lint-proto lint-web ## golangci-lint per module + buf lint + eslint/prettier + tsc
lint-go:
	@for m in $(GO_MODULES); do echo "golangci-lint $$m"; (cd $$m && golangci-lint run ./...); done
lint-proto:
	$(GOTOOL) buf lint $(CURDIR)/proto
lint-web:
	$(PNPM) -r lint
	$(PNPM) -r typecheck
vet: ## go vet every module
	go vet $(GO_PKGS)

.PHONY: fmt
fmt: ## Format Go (gofmt + goimports via golangci-lint), proto (buf format) and web (prettier)
	@for m in $(GO_MODULES); do (cd $$m && golangci-lint fmt ./...); done
	$(GOTOOL) buf format -w $(CURDIR)/proto
	$(PNPM) run format

# ---------------------------------------------------------------------------------------------
.PHONY: gen gen-check
gen: tools ## Regenerate code: protobuf (pkg/gen), OpenAPI (services/*/api/openapi); sqlc later
	cd proto && $(BIN)/buf generate
	@for s in $(OPENAPI_SERVICES); do \
		echo "openapi $$s"; \
		go run ./services/$$s/cmd/$$s openapi > services/$$s/api/openapi/$$s.yaml; \
	done
	@# sqlc: `cd services/<svc> && $(BIN)/sqlc generate` once a service has sqlc.yaml.

gen-check: gen ## Fail if generated code differs from the committed files (CI)
	git diff --exit-code -- pkg/gen services/public-api/api/openapi services/admin-api/api/openapi
	@test -z "$$(git status --porcelain -- pkg/gen services/public-api/api/openapi services/admin-api/api/openapi)" || \
		{ echo "untracked generated files:"; git status --porcelain -- pkg/gen services/*/api/openapi; exit 1; }

# ---------------------------------------------------------------------------------------------
# Images (platform v1). Local tags banking-go/<image>:local; CI/main.yml pushes ghcr.io/<owner>/banking-go/<image>.
GIT_SHA      := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
VERSION      ?= sha-$(shell git rev-parse --short=7 HEAD 2>/dev/null || echo dev)
IMAGE_PREFIX ?= banking-go
IMAGE_TAG    ?= local
GO_IMAGES    := core public-api admin-api mocks
SPA_IMAGES   := web-customer web-admin
IMAGES       := $(GO_IMAGES) $(SPA_IMAGES)
# Forward the host's proxy env to the build (BuildKit predefined args: not kept in image history; none set in CI).
PROXY_BUILD_ARGS := $(foreach v,HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy,$(if $($(v)),--build-arg $(v)))

.PHONY: images images-go images-spa image-smoke
images: images-go images-spa ## Build the 6 images as $(IMAGE_PREFIX)/<image>:$(IMAGE_TAG) (needs Docker buildx)
images-go:
	@for i in $(GO_IMAGES); do \
		echo "== image $$i"; \
		docker buildx build --load -f deploy/docker/go.Dockerfile $(PROXY_BUILD_ARGS) \
			--build-arg SERVICE=$$i --build-arg VERSION=$(VERSION) --build-arg COMMIT=$(GIT_SHA) \
			-t $(IMAGE_PREFIX)/$$i:$(IMAGE_TAG) . || exit 1; \
	done
images-spa:
	@for i in $(SPA_IMAGES); do \
		echo "== image $$i"; \
		docker buildx build --load -f deploy/docker/spa.Dockerfile $(PROXY_BUILD_ARGS) \
			--build-arg APP=$$i -t $(IMAGE_PREFIX)/$$i:$(IMAGE_TAG) . || exit 1; \
	done
image-smoke: ## Run every local image and probe it (make images first)
	VERSION=$(VERSION) scripts/image-smoke.sh $(IMAGE_PREFIX) $(IMAGE_TAG)

# ---------------------------------------------------------------------------------------------
# Helm (platform v1): deploy/helm/_lib is the only place with Kubernetes templates.
HELM_CHARTS := $(sort $(filter-out deploy/helm/_%,$(wildcard deploy/helm/*)))
KUBECONFORM_FLAGS := -strict -summary -kubernetes-version 1.36.0 -schema-location default \
	-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

.PHONY: helm-deps helm-lint helm-test
helm-deps: tools-k8s
	@for c in deploy/helm/_libtest $(HELM_CHARTS); do $(HELM) dependency build $$c >/dev/null || exit 1; done
helm-lint: helm-deps ## helm lint --strict + kubeconform (k8s 1.36 + CRD catalog) of every chart with values-kind.yaml
	@for c in $(HELM_CHARTS); do \
		n=$$(basename $$c); echo "== $$n"; \
		$(HELM) lint --strict $$c -f $$c/values-kind.yaml --set global.ghOwner=lint-owner --set image.tag=lint || exit 1; \
		$(HELM) template $$n $$c -n banking -f $$c/values-kind.yaml --set global.ghOwner=lint-owner --set image.tag=lint \
			| $(KUBECONFORM) $(KUBECONFORM_FLAGS) || exit 1; \
	done
helm-test: helm-deps ## helm-unittest: lib fixture chart + every chart with tests/
	@for c in deploy/helm/_libtest $(HELM_CHARTS); do \
		if [ -d $$c/tests ]; then echo "== $$c"; $(HELM) unittest $$c || exit 1; fi; \
	done

# ---------------------------------------------------------------------------------------------
# kind env (ADR 0011). Never points at another cluster: scripts check the kubectl context.
KIND_CLUSTER := banking-go
GH_OWNER ?=

.PHONY: kind-up kind-down
kind-up: tools-k8s ## Create/refresh the kind cluster (idempotent): k8s 1.36, restore Sealed Secrets key, Argo CD
	deploy/kind/bootstrap.sh
	deploy/kind/check-cluster.sh
kind-down: tools-k8s ## Back up the Sealed Secrets key (if any), then delete the kind cluster (aborts if the backup fails)
	if $(KIND) get clusters 2>/dev/null | grep -qx $(KIND_CLUSTER); then deploy/kind/sealed-key.sh backup; fi
	$(KIND) delete cluster --name $(KIND_CLUSTER)

.PHONY: kind-platform kind-ca
kind-platform: tools-k8s ## Install kind add-ons from deploy/argocd/kind/values.yaml with helm/kubectl (before GitOps; MAX_WAVE=N to stop early)
	scripts/kind-platform.sh $(if $(MAX_WAVE),--max-wave $(MAX_WAVE))
	deploy/kind/check-platform.sh
kind-ca: tools-k8s ## Export the kind root CA to ~/.config/banking-go/kind-ca.crt (curl --cacert / trust store)
	@mkdir -p $(HOME)/.config/banking-go
	$(KUBECTL) --context kind-$(KIND_CLUSTER) -n cert-manager get secret kind-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > $(HOME)/.config/banking-go/kind-ca.crt
	@echo "CA: $(HOME)/.config/banking-go/kind-ca.crt — e.g. curl --cacert $(HOME)/.config/banking-go/kind-ca.crt https://api.kind.localhost/v1/ping"

.PHONY: seal
seal: tools-k8s ## Seal kind secrets from deploy/secrets/kind.env (git-ignored) into deploy/secrets/kind/*.sealed.yaml
	scripts/seal-kind.sh

.PHONY: kind-load kind-apps
kind-load: tools-k8s ## Load the locally built images ($(IMAGE_PREFIX)/<image>:$(IMAGE_TAG)) into the kind nodes
	@for i in $(IMAGES); do $(KIND) load docker-image $(IMAGE_PREFIX)/$$i:$(IMAGE_TAG) --name $(KIND_CLUSTER) || exit 1; done
kind-apps: tools-k8s ## helm upgrade --install the 10 charts with values-kind.yaml + local images (before GitOps)
	IMAGE_PREFIX=$(IMAGE_PREFIX) IMAGE_TAG=$(IMAGE_TAG) scripts/kind-apps.sh
	deploy/kind/check-apps.sh

.PHONY: kind-smoke
kind-smoke: tools-k8s ## Smoke the kind env: 4 hosts via Traefik, migration Jobs, running digests vs deploy/releases/kind.yaml
	scripts/kind-smoke.sh

# ---------------------------------------------------------------------------------------------
.PHONY: up up-obs down run
up: ## Start local deps (postgres, rabbitmq, seaweedfs) and wait until healthy
	$(COMPOSE) up -d --wait
up-obs: ## Start local deps + OpenTelemetry Collector (profile obs)
	$(COMPOSE) --profile obs up -d --wait
down: ## Stop local deps (keeps volumes; add `-v` by hand to wipe data)
	$(COMPOSE) --profile obs down

run: up ## Start deps, then print how to run each service
	@echo ""
	@echo "Dependencies are up. Run each deployable in its own terminal (env: cp .env.example .env; set -a; . ./.env; set +a):"
	@echo "  go run ./services/core/cmd/core                 # gRPC :8090, admin :9190"
	@echo "  go run ./services/core/cmd/core-worker          # admin :9191"
	@echo "  go run ./services/public-api/cmd/public-api     # HTTP :8081, admin :9181"
	@echo "  go run ./services/admin-api/cmd/admin-api       # HTTP :8082, admin :9182"
	@echo "  go run ./services/mocks/cmd/mock-napas          # HTTP :8101, admin :9201 (ekyc :8102/:9202, otp :8103/:9203, gateway :8104/:9204)"
	@echo "  $(PNPM) --filter @banking-go/web-customer dev   # http://localhost:5173"
	@echo "  $(PNPM) --filter @banking-go/web-admin dev      # http://localhost:5174"
	@echo "Telemetry: make up-obs and export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 OTEL_EXPORTER_OTLP_INSECURE=true"
