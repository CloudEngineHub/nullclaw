COMPOSE ?= docker compose
BUILDX ?= docker buildx
IMAGE ?= nullclaw:local
DOCKER_TARGET ?= release
VERSION ?= dev
PROFILE ?= gateway
SERVICE ?= gateway
RUN_ARGS ?=
COMPOSE_BAKE ?= true
NULLCLAW_PORT ?= 3210

export COMPOSE_BAKE
export NULLCLAW_IMAGE := $(IMAGE)
export NULLCLAW_DOCKER_TARGET := $(DOCKER_TARGET)
export NULLCLAW_VERSION := $(VERSION)
export NULLCLAW_PORT

.PHONY: build up down run shell logs check-buildx

check-buildx:
	$(BUILDX) version >/dev/null

build: check-buildx
	$(COMPOSE) --profile $(PROFILE) build $(SERVICE)

up: check-buildx
	$(COMPOSE) --profile $(PROFILE) up -d --build $(SERVICE)

down:
	$(COMPOSE) down

run:
	$(COMPOSE) --profile agent run --rm agent $(RUN_ARGS)

shell:
	$(COMPOSE) --profile agent run --rm --entrypoint /bin/sh agent

logs:
	$(COMPOSE) --profile $(PROFILE) logs -f $(SERVICE)
