# Makefile for building/pushing the single Alpine image from repo root

# ---- Registry / Image -------------------------------------------------------
DOCKER_REPO ?= peetvandesande/pg-backup
VARIANT     ?= alpine

# ---- Build platforms --------------------------------------------------------
BUILD_PLATFORM ?= linux/amd64
PLATFORMS      ?= linux/amd64,linux/arm64

# ---- Git metadata -----------------------------------------------------------
BRANCH   := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
SANITIZED_BRANCH := $(subst /,-,$(BRANCH))          # docker-safe branch tag
GIT_SHA  := $(shell git rev-parse --short=8 HEAD 2>/dev/null)
GIT_TAG  := $(shell git describe --tags --abbrev=0 2>/dev/null)
GIT_REF  := $(shell git describe --tags --always --dirty --abbrev=8 2>/dev/null)

# ---- Tags (clean + deduped) -------------------------------------------------
# You may override explicitly: make push TAGS="dev dev-$(VARIANT)"
ifeq ($(origin TAGS), undefined)
  ifeq ($(BRANCH),dev)
    TAGS := \
      dev \
      dev-$(VARIANT) \
      dev-$(VARIANT)-$(GIT_SHA) \
      dev-$(GIT_SHA)
  else ifeq ($(BRANCH),main)
    ifneq ($(strip $(GIT_TAG)),)
      TAGS := \
        latest \
        $(VARIANT) \
        $(GIT_TAG) \
        $(GIT_TAG)-$(VARIANT) \
        $(GIT_TAG)-$(VARIANT)-$(GIT_SHA) \
        $(GIT_SHA)
    else
      TAGS := \
        latest \
        $(VARIANT) \
        $(VARIANT)-$(GIT_SHA) \
        $(GIT_SHA)
    endif
  else
    TAGS := \
      $(SANITIZED_BRANCH) \
      $(SANITIZED_BRANCH)-$(VARIANT) \
      $(SANITIZED_BRANCH)-$(GIT_SHA)
  endif
endif

# Expand to -t args (no extra spaces)
TFLAGS := $(foreach t,$(TAGS),-t $(DOCKER_REPO):$(t))

# ---- OCI labels -------------------------------------------------------------
REPO_URL  := $(shell git config --get remote.origin.url 2>/dev/null)
BUILD_DATE:= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
BUILD_OPTS ?= \
  --label org.opencontainers.image.title="pg-backup" \
  --label org.opencontainers.image.description="PostgreSQL backup/restore (client-only) on Alpine" \
  --label org.opencontainers.image.url="$(REPO_URL)" \
  --label org.opencontainers.image.source="$(REPO_URL)" \
  --label org.opencontainers.image.revision="$(GIT_SHA)" \
  --label org.opencontainers.image.version="$(GIT_TAG)" \
  --label org.opencontainers.image.created="$(BUILD_DATE)"

# ---- Safety: block dirty tree on main ---------------------------------------
# Set BUILD_DIRTY_OK=1 to bypass (e.g., make push BUILD_DIRTY_OK=1)
.PHONY: assert-clean
assert-clean:
	@if [ "$(BRANCH)" = "main" ] && [ -z "$(BUILD_DIRTY_OK)" ]; then \
	  git diff-index --quiet HEAD -- || { \
	    echo "Refusing to build on 'main' with a dirty working tree (set BUILD_DIRTY_OK=1 to override)"; \
	    exit 1; \
	  }; \
	fi

# ---- buildx helper ----------------------------------------------------------
.PHONY: buildx-create
buildx-create:
	@docker buildx inspect multiarch >/dev/null 2>&1 || docker buildx create --name multiarch --use
	@docker buildx use multiarch >/dev/null 2>&1 || true

# ---- Local build (load) -----------------------------------------------------
.PHONY: build
build: assert-clean buildx-create
	docker buildx build \
	  --builder multiarch \
	  --platform $(BUILD_PLATFORM) \
	  --load \
	  $(BUILD_OPTS) \
	  $(TFLAGS) \
	  -f alpine/Dockerfile \
	  .

# ---- Multi-arch push --------------------------------------------------------
.PHONY: push
push: assert-clean buildx-create
	docker buildx build \
	  --builder multiarch \
	  --platform $(PLATFORMS) \
	  --push \
	  $(BUILD_OPTS) \
	  $(TFLAGS) \
	  -f alpine/Dockerfile \
	  .

# ---- Utilities --------------------------------------------------------------
.PHONY: print
print:
	@echo "Repo:     $(DOCKER_REPO)"
	@echo "Branch:   $(BRANCH)"
	@echo "Git tag:  $(GIT_TAG)"
	@echo "Git ref:  $(GIT_REF)"
	@echo "Git sha:  $(GIT_SHA)"
	@echo "Variant:  $(VARIANT)"
	@echo "Tags:"
	@$(foreach t,$(TAGS),echo "  - $(t)";)
	@echo "Platforms(build): $(BUILD_PLATFORM)"
	@echo "Platforms(push):  $(PLATFORMS)"

.PHONY: tag-list
tag-list:
	@$(foreach t,$(TAGS),echo $(DOCKER_REPO):$(t);)

# --- Release ------------------------------------------------------------------

# Version must be passed, e.g.:
#   make release VERSION=1.2.3
VERSION ?=

release: check-version confirm-release tag-version build-multi push-images push-tag
	@echo "✅ Release completed successfully."

check-version:
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: VERSION must be specified (example: make release VERSION=1.2.3)"; \
		exit 1; \
	fi
	@if ! echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "ERROR: VERSION must follow semantic versioning (e.g., 1.2.3)"; \
		exit 1; \
	fi

confirm-release:
	@echo "Releasing version v$(VERSION) for repository $(REPO)"
	@printf "Proceed? (y/N) "; read ans; [ "$$ans" = "y" ]

tag-version:
	git tag -a v$(VERSION) -m "Release v$(VERSION)"
	git push --tags

build-multi:
	docker buildx build \
		--builder multiarch \
		--platform linux/amd64,linux/arm64 \
		--label org.opencontainers.image.version="v$(VERSION)" \
		-t $(REPO):v$(VERSION) \
		-t $(REPO):latest \
		--push .

push-images:
	@echo "Images already pushed in build step."

push-tag:
	@echo "Tag pushed to git: v$(VERSION)"
