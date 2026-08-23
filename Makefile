SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

IMAGE ?= cyberschmutz
PORT ?= 8080
SITE_PORT ?= 4000
LIVERELOAD_PORT ?= 35729

.PHONY: help install serve build check clean docker-build docker-check docker-up docker-down docker-logs docker-serve watch watch-logs deploy

help: ## Show available targets.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make <target> [VARIABLE=value]\n\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  %-16s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf "\nVariables: IMAGE=%s PORT=%s SITE_PORT=%s LIVERELOAD_PORT=%s\n" "$(IMAGE)" "$(PORT)" "$(SITE_PORT)" "$(LIVERELOAD_PORT)"

install: ## Install Ruby dependencies locally.
	bundle install

serve: ## Run Jekyll locally on SITE_PORT (default: 4000) with live reload.
	bundle exec jekyll serve --livereload --host 0.0.0.0 --port $(SITE_PORT) --livereload-port $(LIVERELOAD_PORT)

build: ## Build the production site into _site/.
	JEKYLL_ENV=production bundle exec jekyll build

check: build ## Validate generated HTML locally (external links are skipped).
	bundle exec htmlproofer _site --disable-external=true --ignore-urls '/^http:\/\/127.0.0.1/,/^http:\/\/0.0.0.0/,/^http:\/\/localhost/'

clean: ## Remove generated local Jekyll output.
	rm -rf _site .jekyll-cache

docker-build: ## Build the production Docker image.
	IMAGE_NAME=$(IMAGE) docker compose build site

docker-check: ## Build and validate the site entirely inside Docker.
	docker build --target test --tag $(IMAGE):check .

docker-up: ## Start the production site on PORT (default: 8080).
	IMAGE_NAME=$(IMAGE) PORT=$(PORT) docker compose up --build --detach site

docker-down: ## Stop and remove the local deployment.
	docker compose down --remove-orphans

docker-logs: ## Follow production container logs.
	docker compose logs --follow --tail=100 site

docker-serve: ## Run Jekyll in Docker with live reload.
	SITE_PORT=$(SITE_PORT) LIVERELOAD_PORT=$(LIVERELOAD_PORT) docker compose --profile dev up --build blog

watch: ## Start an auto-updating Jekyll preview on SITE_PORT (default: 4000).
	SITE_PORT=$(SITE_PORT) LIVERELOAD_PORT=$(LIVERELOAD_PORT) docker compose --profile dev up --build --detach blog

watch-logs: ## Follow logs for the auto-updating preview.
	docker compose logs --follow --tail=100 blog

deploy: docker-check docker-up ## Validate, build, and launch the Docker deployment.
	@printf "Deployment is live at http://localhost:%s\n" "$(PORT)"
