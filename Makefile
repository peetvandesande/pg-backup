# Makefile for building/pushing the single Alpine image from repo root

DOCKER_REPO ?= peetvandesande/pg-backup
TAG_ALPINE  ?= alpine
LATEST_TAG  ?= latest

# Local build (load into docker)
BUILD_PLATFORM ?= linux/amd64
# Remote multi-arch push
PLATFORMS ?= linux/amd64,linux/arm64

IMAGE_ALPINE := $(DOCKER_REPO):$(TAG_ALPINE)
IMAGE_ALPINE_LATEST := $(DOCKER_REPO):$(LATEST_TAG)

# Labels
GIT_SHA  := $(shell git rev-parse --short=8 HEAD 2>/dev/null)
BUILD_OPTS := --label org.opencontainers.image.revision=$(GIT_SHA)

.PHONY: help
help:
	@echo "Targets:"
	@echo "  buildx-create     Create/select buildx builder 'multiarch'"
	@echo "  build             Build Alpine image locally (--load)"
	@echo "  push              Build+push Alpine (multi-arch)"
	@echo ""
	@echo "Vars:"
	@echo "  DOCKER_REPO=$(DOCKER_REPO)"
	@echo "  TAG_ALPINE=$(TAG_ALPINE)"
	@echo "  BUILD_PLATFORM=$(BUILD_PLATFORM)"
	@echo "  PLATFORMS=$(PLATFORMS)"

.PHONY: buildx-create
buildx-create:
	@if ! docker buildx inspect multiarch >/dev/null 2>&1; then \
	  docker buildx create --name multiarch --use >/dev/null; \
	  echo "Created and selected buildx builder 'multiarch'"; \
	else \
	  docker buildx use multiarch >/dev/null; \
	  echo "Using existing buildx builder 'multiarch'"; \
	fi

.PHONY: build
build: buildx-create
	docker buildx build \
	  --builder multiarch \
	  --platform $(BUILD_PLATFORM) \
	  --load \
	  $(BUILD_OPTS) \
	  -t $(IMAGE_ALPINE) \
	  -t $(IMAGE_ALPINE_LATEST) \
	  -f alpine/Dockerfile \
	  .

.PHONY: push
push: buildx-create
	docker buildx build \
	  --builder multiarch \
	  --platform $(PLATFORMS) \
	  --push \
	  $(BUILD_OPTS) \
	  -t $(IMAGE_ALPINE) \
	  -t $(IMAGE_ALPINE_LATEST) \
	  -f alpine/Dockerfile \
	  .