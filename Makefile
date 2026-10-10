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

# Every recipe runs in bash with -e -u -o pipefail. Through a tiny wrapper rather than .SHELLFLAGS, because the
# GNU make that ships with macOS is 3.81, which ignores .SHELLFLAGS (and macOS's /bin/bash is 3.2: recipes and
# scripts here stick to bash 3.2 features: no mapfile, no associative arrays, no ${x,,}).
SHELL := $(CURDIR)/tools/setup/shell.sh
.DEFAULT_GOAL := help

# ---- Which computer is this? ---------------------------------------------------
# Linux (x86_64) and macOS (Apple Silicon arm64 or Intel x86_64). Everything below picks its downloads from these.
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_S),Darwin)
  HOST_OS   := mac
  HOST_NAME := Mac ($(UNAME_M))
else
  HOST_OS   := linux
  HOST_NAME := Linux ($(UNAME_M))
endif

# ---- Pinned toolchain ---------------------------------------------------------
# To upgrade Godot: change GODOT_VERSION, re-pin the template hashes (TEMPLATE_SHAS, see tools/setup/zip_members.py
# --print-sha), run `make bootstrap`, then `make check`.
GODOT_VERSION  := 4.7.2
GODOT_FLAVOR   := stable
GODOT_TAG      := $(GODOT_VERSION)-$(GODOT_FLAVOR)

TOOLS_DIR      := .tools
TOOLS_BIN      := $(TOOLS_DIR)/bin
DOWNLOADS      := $(TOOLS_DIR)/downloads
GODOT_HOME     := $(TOOLS_DIR)/godot-$(GODOT_TAG)
RELEASE_URL    := https://github.com/godotengine/godot/releases/download/$(GODOT_TAG)
TEMPLATES_TPZ  := Godot_v$(GODOT_TAG)_export_templates.tpz
# Self-contained mode keeps editor data (incl. export templates) beside the editor, in $(GODOT_HOME)/editor_data.
# On macOS Godot looks for the `._sc_` marker next to Godot.app (the bundle itself is read-only).
TEMPLATES_DIR  := $(GODOT_HOME)/editor_data/export_templates/$(GODOT_VERSION).$(GODOT_FLAVOR)
TEMPLATES_OK   := $(TEMPLATES_DIR)/.installed
ifeq ($(HOST_OS),mac)
  EDITOR_ZIP     := Godot_v$(GODOT_TAG)_macos.universal.zip
  GODOT          := $(GODOT_HOME)/Godot.app/Contents/MacOS/Godot
else
  EDITOR_ZIP     := Godot_v$(GODOT_TAG)_linux.x86_64.zip
  GODOT          := $(GODOT_HOME)/Godot_v$(GODOT_TAG)_linux.x86_64
endif
# Only the export templates we use are fetched out of the 1.3 GB .tpz (HTTP range requests,
# tools/setup/zip_members.py), each checked against the sha256 pinned here. They were pinned from members that
# matched the copies extracted from the SHA512-verified .tpz byte for byte (2026-10-10).
# Web (single-threaded: any static host) everywhere; macOS desktop everywhere (so Linux can build the Mac game
# too); Linux desktop on Linux only.
TEMPLATE_FILES := web_nothreads_debug.zip web_nothreads_release.zip macos.zip version.txt
ifeq ($(HOST_OS),linux)
  TEMPLATE_FILES += linux_debug.x86_64 linux_release.x86_64
endif
TEMPLATE_SHAS  := web_nothreads_debug.zip=08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a \
                  web_nothreads_release.zip=d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0 \
                  macos.zip=88df5e2e6fee99088699be66e6d42e4da4fb0c5619d054297d755a49558a4792 \
                  version.txt=38885c88f75abbc797a1db7559719800279a00cfb9fa8b2e2868a7f6f84bad2e \
                  linux_debug.x86_64=1a291d3d15e4180b60b0af96cf6458f11fe143636d76575ddf1e23d1a3f24f2e \
                  linux_release.x86_64=d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63

# GitHub's command-line tool, project-local like Godot: signing in, making the kid's repo, backups. (_agents/git.md)
GH_VERSION     := 2.102.0
GH_HOME        := $(TOOLS_DIR)/gh-$(GH_VERSION)
GH             := $(GH_HOME)/bin/gh
GH_URL         := https://github.com/cli/cli/releases/download/v$(GH_VERSION)
ifeq ($(HOST_OS),mac)
  GH_ARCHIVE   := gh_$(GH_VERSION)_macOS_$(if $(filter arm64,$(UNAME_M)),arm64,amd64).zip
else
  GH_ARCHIVE   := gh_$(GH_VERSION)_linux_amd64.tar.gz
endif
export GH

# A project-local Python 3.12 (macOS ships 3.9; Linux distros vary): uv installs it into .tools, plus a venv.
UV_VERSION     := 0.13.0
ifeq ($(HOST_OS),mac)
  UV_TRIPLE    := $(if $(filter arm64,$(UNAME_M)),aarch64,x86_64)-apple-darwin
else
  UV_TRIPLE    := $(if $(filter aarch64 arm64,$(UNAME_M)),aarch64,x86_64)-unknown-linux-gnu
endif
UV             := $(TOOLS_DIR)/uv-$(UV_VERSION)/uv
PYTHON_VERSION := 3.12
VENV           := $(TOOLS_DIR)/python$(PYTHON_VERSION)-venv
VENV_PY        := $(VENV)/bin/python

# ffmpeg/ffprobe (the audio tools and choices pages need them). The system's if it has them (Linux: apt install
# ffmpeg), else a pinned static build into .tools/bin (macOS, no Homebrew needed): ffmpeg.martin-riedl.de.
FFMPEG_BASE    := https://ffmpeg.martin-riedl.de/download
ifeq ($(HOST_OS),mac)
  ifeq ($(UNAME_M),arm64)
    FFMPEG_DIR   := macos/arm64/1789931890_9.0.2
    FFMPEG_SHA   := c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924
    FFPROBE_SHA  := fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6
  else
    FFMPEG_DIR   := macos/amd64/1789931006_9.0.2
    FFMPEG_SHA   := 7c6b4125b191cbf773832dc51f424cf2b6bb7da43007d1e066f95909e47cacd4
    FFPROBE_SHA  := 2322438ed2f6319a691291b247d09c69dcaa3a982460d1f269a7e1af335cfdfd
  endif
else
  FFMPEG_DIR     := linux/amd64/1789931100_9.0.2
  FFMPEG_SHA     := fa8ecf4abbd290d98f7d188b8649cc6b391ae209a98452be955a15aab1909d7f
  FFPROBE_SHA    := 3f428c49070be3d24ec338602b76d412e401ffcb8a5641ef0e729181a232fc32
endif

# .tools/bin first on PATH, so our ffmpeg (if downloaded) is the one every tool finds.
export PATH := $(CURDIR)/$(TOOLS_BIN):$(PATH)

BUILD_DIR      := build
# ONE headless Godot at a time per checkout. Two Godot processes importing into the same .godot/ cache corrupt it,
# and the symptom (missing resources, "Nonexistent function") reads exactly like broken code (Tank Squad lost an
# evening to it). Every headless Godot command goes through $(LOCK); windowed play (run, editor) does not.
# LOCK and TIMEOUT are small Python helpers (flock and timeout are GNU-only; macOS has neither). They run on the
# system python3 on purpose: they are needed before the project's own Python exists.
$(shell mkdir -p $(BUILD_DIR) && touch $(BUILD_DIR)/.gdignore)
LOCK           := python3 $(CURDIR)/tools/setup/lock.py $(CURDIR)/$(BUILD_DIR)/.godot.lock
TIMEOUT        := python3 $(CURDIR)/tools/setup/timeout.py
# The project's Python when installed (make python), else the system's.
PYTHON         ?= $(if $(wildcard $(VENV_PY)),$(CURDIR)/$(VENV_PY),python3)
NODE           ?= node
NPM            ?= npm
ifeq ($(HOST_OS),mac)
  CHROME       ?= /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
else
  CHROME       ?= /usr/bin/google-chrome
endif
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
