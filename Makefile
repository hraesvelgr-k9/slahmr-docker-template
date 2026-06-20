# ============================================================
# SLAHMR Docker – Makefile
# Usage: make help
# ============================================================

ifneq (,$(wildcard .env))
include .env
export
endif

COMPOSE    := docker compose --env-file .env
BASE_FILES := -f compose.yml
DEV_FILES  := $(BASE_FILES) -f compose.dev.yml
PROD_FILES := $(BASE_FILES) -f compose.prod.yml
SERVICE    := slahmr
REPO_DIR   := workspace/slahmr

.PHONY: help env-init init setup reinit \
        dev-build dev-up dev-down dev-shell dev-logs dev-config dev-rebuild dev-restart \
        prod-build prod-up prod-down prod-shell prod-logs prod-config prod-rebuild \
        prepare-custom prepare-video run-custom run-video \
        clean-pycache ps clean

# ------------------------------------------------------------
help:
	@echo ""
	@echo "SLAHMR Docker Makefile"
	@echo "======================================================"
	@echo "Setup"
	@echo "  make env-init          Copy .env.example -> .env (if absent)"
	@echo "  make init              Clone SLAHMR source into workspace/slahmr"
	@echo "  make setup             Run setup.sh (clone + copy entrypoints + download weights)"
	@echo "  make reinit            Remove workspace/slahmr and re-clone from scratch"
	@echo "  make clean-pycache     Remove root-owned __pycache__ dirs via a temporary container"
	@echo ""
	@echo "Development (dev target)"
	@echo "  make dev-build         Build dev image"
	@echo "  make dev-up            Start dev container (detached)"
	@echo "  make dev-down          Stop dev container"
	@echo "  make dev-shell         Open bash in running dev container"
	@echo "  make dev-logs          Tail dev container logs"
	@echo "  make dev-config        Show merged dev Compose config"
	@echo "  make dev-rebuild       Rebuild and restart dev container"
	@echo "  make dev-restart       Re-run bootstrap (reset stamp + restart)"
	@echo ""
	@echo "Production (prod target)"
	@echo "  make prod-build        Build prod image"
	@echo "  make prod-up           Start prod container (detached)"
	@echo "  make prod-down         Stop prod container"
	@echo "  make prod-shell        Open bash in running prod container"
	@echo "  make prod-logs         Tail prod container logs"
	@echo "  make prod-config       Show merged prod Compose config"
	@echo "  make prod-rebuild      Rebuild and restart prod container"
	@echo ""
	@echo "Preprocessing & Inference"
	@echo "  make prepare-custom    Run prepare_custom.sh  VIDEO=<path> [SEQ=<name>]"
	@echo "  make prepare-video     Run prepare_video.sh   VIDEO=<path> [SEQ=<name>] [FPS=<fps>]"
	@echo "  make run-custom        Run run_custom_demo.sh"
	@echo "  make run-video         Run run_video_demo.sh"
	@echo ""
	@echo "Utilities"
	@echo "  make ps                Show container status"
	@echo "  make clean             Remove containers and named volumes"
	@echo ""

# ------------------------------------------------------------
# Setup
# ------------------------------------------------------------
env-init:
	@test -f .env || (cp .env.example .env && echo "[INFO] .env created from .env.example")

init:
	@test -d $(REPO_DIR) || (mkdir -p workspace && git clone --recursive https://github.com/hraesvelgr-k9/slahmr.git $(REPO_DIR) && echo "[INFO] SLAHMR cloned into $(REPO_DIR)")

setup:
	bash setup.sh

# Remove root-owned __pycache__ files generated inside the container,
# then re-clone the SLAHMR source tree from scratch.
reinit: clean-pycache
	@echo "[WARN] Recreating $(REPO_DIR) from scratch..."
	rm -rf $(REPO_DIR)
	$(MAKE) init
	$(MAKE) setup

# Use a temporary Alpine container (runs as root) to delete
# __pycache__ directories that were created by the container user
# and cannot be removed by the host user.
clean-pycache:
	@if find $(REPO_DIR) -name '__pycache__' -print -quit 2>/dev/null | grep -q .; then \
		echo "[INFO] Removing root-owned __pycache__ via temporary container..."; \
		docker run --rm \
			-v "$(CURDIR)/$(REPO_DIR):/target" \
			alpine:latest \
			sh -c "find /target -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null; true"; \
		echo "[INFO] __pycache__ cleanup done."; \
	else \
		echo "[INFO] No __pycache__ found, nothing to clean."; \
	fi

# ------------------------------------------------------------
# Dev
# ------------------------------------------------------------
dev-build:
	$(COMPOSE) $(DEV_FILES) build

dev-up:
	$(COMPOSE) $(DEV_FILES) up -d

dev-down:
	$(COMPOSE) $(DEV_FILES) down

dev-shell:
	$(COMPOSE) $(DEV_FILES) exec $(SERVICE) bash

dev-logs:
	$(COMPOSE) $(DEV_FILES) logs -f

dev-config:
	$(COMPOSE) $(DEV_FILES) config

dev-rebuild:
	$(COMPOSE) $(DEV_FILES) up -d --build

dev-restart:
	$(COMPOSE) $(DEV_FILES) exec $(SERVICE) rm -f /var/lib/slahmr/.deps_installed
	$(COMPOSE) $(DEV_FILES) restart $(SERVICE)

# ------------------------------------------------------------
# Prod
# ------------------------------------------------------------
prod-build:
	$(COMPOSE) $(PROD_FILES) build

prod-up:
	$(COMPOSE) $(PROD_FILES) up -d

prod-down:
	$(COMPOSE) $(PROD_FILES) down

prod-shell:
	$(COMPOSE) $(PROD_FILES) exec $(SERVICE) bash

prod-logs:
	$(COMPOSE) $(PROD_FILES) logs -f

prod-config:
	$(COMPOSE) $(PROD_FILES) config

prod-rebuild:
	$(COMPOSE) $(PROD_FILES) up -d --build

# ------------------------------------------------------------
# Preprocessing
# VIDEO=<path inside container or relative>  (required)
# SEQ=<sequence name>                        (optional, default: basename of VIDEO)
# FPS=<fps>                                  (optional, prepare_video only)
# ------------------------------------------------------------
VIDEO ?=
SEQ   ?=
FPS   ?=

prepare-custom:
	@test -n "$(VIDEO)" || (echo "[ERROR] VIDEO is required.  e.g.: make prepare-custom VIDEO=/workspace/data/inputs/sample.mp4" && exit 1)
	$(COMPOSE) $(DEV_FILES) run --rm $(SERVICE) bash /workspace/slahmr/scripts/prepare_custom.sh "$(VIDEO)" $(if $(SEQ),"$(SEQ)",)

prepare-video:
	@test -n "$(VIDEO)" || (echo "[ERROR] VIDEO is required.  e.g.: make prepare-video VIDEO=/workspace/data/inputs/sample.mp4" && exit 1)
	$(COMPOSE) $(DEV_FILES) run --rm $(SERVICE) bash /workspace/slahmr/scripts/prepare_video.sh "$(VIDEO)" $(if $(SEQ),"$(SEQ)",) $(if $(FPS),"$(FPS)",)

# ------------------------------------------------------------
# Inference
# ------------------------------------------------------------
run-custom:
	$(COMPOSE) $(DEV_FILES) run --rm $(SERVICE) bash /workspace/slahmr/scripts/run_custom_demo.sh

run-video:
	$(COMPOSE) $(DEV_FILES) run --rm $(SERVICE) bash /workspace/slahmr/scripts/run_video_demo.sh

# ------------------------------------------------------------
# Utilities
# ------------------------------------------------------------
ps:
	$(COMPOSE) $(DEV_FILES) ps

clean:
	$(COMPOSE) $(DEV_FILES) down -v --remove-orphans || true
	$(COMPOSE) $(PROD_FILES) down -v --remove-orphans || true
