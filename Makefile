# Game Foundation: project Makefile
#
# Every workflow in this project is a make target. `make help` lists them all.
# A fresh clone needs exactly one setup step:
#
#     make bootstrap
#
# which downloads a PINNED Godot editor plus only the export templates we use into ./.tools
# (Godot "self-contained mode": nothing is written to ~/.local or ~/.config).
# Why each choice was made: _agents/bootstrap.md.
#
# Targets live in mk/*.mk, one file per area. Add a new target to the right file with a `## help text`
# comment so `make help` shows it. If you find yourself typing a long command twice, it becomes a target.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# ---- Pinned toolchain ---------------------------------------------------------
# To upgrade Godot: change GODOT_VERSION, run `make bootstrap`, then `make check`.
GODOT_VERSION  := 4.7.2
GODOT_FLAVOR   := stable
GODOT_TAG      := $(GODOT_VERSION)-$(GODOT_FLAVOR)
GODOT_PLATFORM := linux.x86_64

TOOLS_DIR      := .tools
DOWNLOADS      := $(TOOLS_DIR)/downloads
GODOT_HOME     := $(TOOLS_DIR)/godot-$(GODOT_TAG)
GODOT          := $(GODOT_HOME)/Godot_v$(GODOT_TAG)_$(GODOT_PLATFORM)
TEMPLATES_DIR  := $(GODOT_HOME)/editor_data/export_templates/$(GODOT_VERSION).$(GODOT_FLAVOR)
TEMPLATES_OK   := $(TEMPLATES_DIR)/.installed
RELEASE_URL    := https://github.com/godotengine/godot/releases/download/$(GODOT_TAG)
EDITOR_ZIP     := Godot_v$(GODOT_TAG)_$(GODOT_PLATFORM).zip
TEMPLATES_TPZ  := Godot_v$(GODOT_TAG)_export_templates.tpz
# Only what we export with: single-threaded web (works on any static host) + Linux desktop.
TEMPLATE_FILES := web_nothreads_debug.zip web_nothreads_release.zip \
                  linux_debug.x86_64 linux_release.x86_64 version.txt

# GitHub's command-line tool, project-local like Godot: signing in, making the kid's repo, backups. (_agents/git.md)
GH_VERSION     := 2.102.0
GH_HOME        := $(TOOLS_DIR)/gh-$(GH_VERSION)
GH             := $(GH_HOME)/bin/gh
GH_TGZ         := gh_$(GH_VERSION)_linux_amd64.tar.gz
GH_URL         := https://github.com/cli/cli/releases/download/v$(GH_VERSION)
export GH

BUILD_DIR      := build
# ONE headless Godot at a time per checkout. Two Godot processes importing into the same .godot/ cache corrupt it,
# and the symptom (missing resources, "Nonexistent function") reads exactly like broken code (Tank Squad lost an
# evening to it). Every headless Godot command goes through $(LOCK); windowed play (run, editor) does not.
$(shell mkdir -p $(BUILD_DIR) && touch $(BUILD_DIR)/.gdignore)
LOCK           := flock $(BUILD_DIR)/.godot.lock
PYTHON         ?= python3
NODE           ?= node
NPM            ?= npm
CHROME         ?= /usr/bin/google-chrome
WEB_PORT       ?= 8060
WEB_HOST       ?= 127.0.0.1

# API keys come from the environment (never the repo). Put them in ~/.config/game-foundation/keys.env:
#   export MESHY_API_KEY=...
#   export ELEVENLABS_API_KEY=...
KEYS_FILE      ?= $(HOME)/.config/game-foundation/keys.env
ifneq ($(wildcard $(KEYS_FILE)),)
  include $(KEYS_FILE)
  export MESHY_API_KEY ELEVENLABS_API_KEY
endif

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

include mk/*.mk
