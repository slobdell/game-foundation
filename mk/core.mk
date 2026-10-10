# Toolchain, lint, tests, the check, cleanup.

.PHONY: bootstrap doctor import lint test py-test check check-all clean distclean

# ---- Bootstrap ----------------------------------------------------------------

bootstrap: python ffmpeg $(GODOT) $(TEMPLATES_OK) gh import doctor ## Install everything into ./.tools (Godot, templates, Python, ffmpeg, gh; no admin needed), import the project

$(DOWNLOADS)/SHA512-SUMS.txt:
	mkdir -p $(DOWNLOADS)
	curl -fsSL --retry 3 -o $@ $(RELEASE_URL)/SHA512-SUMS.txt

$(GODOT): $(DOWNLOADS)/SHA512-SUMS.txt
	@echo ">> Downloading Godot $(GODOT_TAG) editor for $(HOST_NAME)"
	curl -fL --retry 3 -C - -o $(DOWNLOADS)/$(EDITOR_ZIP) $(RELEASE_URL)/$(EDITOR_ZIP)
	cd $(DOWNLOADS) && grep " $(EDITOR_ZIP)$$" SHA512-SUMS.txt | shasum -a 512 -c -
	mkdir -p $(GODOT_HOME)
ifeq ($(HOST_OS),mac)
	@# ditto, not unzip: it keeps the app bundle's symlinks, permissions and code signature intact.
	ditto -x -k $(DOWNLOADS)/$(EDITOR_ZIP) $(GODOT_HOME)
else
	unzip -o -q $(DOWNLOADS)/$(EDITOR_ZIP) -d $(GODOT_HOME)
endif
	touch $(GODOT_HOME)/._sc_
	rm -f $(DOWNLOADS)/$(EDITOR_ZIP)
	test -x $@ && touch $@

$(TEMPLATES_OK):
	@echo ">> Fetching only the export templates we use (not the whole 1.3 GB): $(TEMPLATE_FILES)"
	mkdir -p $(TEMPLATES_DIR)
	python3 tools/setup/zip_members.py $(RELEASE_URL)/$(TEMPLATES_TPZ) $(TEMPLATES_DIR) \
		$(foreach f,$(TEMPLATE_FILES),--member templates/$(f)) $(foreach s,$(TEMPLATE_SHAS),--sha $(s))
	$(if $(filter linux,$(HOST_OS)),chmod +x $(TEMPLATES_DIR)/linux_*.x86_64)
	touch $@

# ---- Project-local Python (uv) and ffmpeg ------------------------------------------

.PHONY: python ffmpeg

python: $(VENV_PY) ## Install the project's own Python $(PYTHON_VERSION) into .tools (via uv; no admin needed)

$(UV):
	@echo ">> Downloading uv $(UV_VERSION) (installs the project's Python)"
	mkdir -p $(DOWNLOADS) $(dir $(UV))
	curl -fsSL --retry 3 -o $(DOWNLOADS)/uv-$(UV_TRIPLE).tar.gz https://github.com/astral-sh/uv/releases/download/$(UV_VERSION)/uv-$(UV_TRIPLE).tar.gz
	curl -fsSL --retry 3 -o $(DOWNLOADS)/uv-$(UV_TRIPLE).tar.gz.sha256 https://github.com/astral-sh/uv/releases/download/$(UV_VERSION)/uv-$(UV_TRIPLE).tar.gz.sha256
	cd $(DOWNLOADS) && shasum -a 256 -c uv-$(UV_TRIPLE).tar.gz.sha256
	tar -xzf $(DOWNLOADS)/uv-$(UV_TRIPLE).tar.gz -C $(dir $(UV)) --strip-components=1
	rm -f $(DOWNLOADS)/uv-$(UV_TRIPLE).tar.gz*
	test -x $@ && touch $@

# Everything uv writes stays in .tools (its cache and the Python it downloads), like the rest of the toolchain.
$(VENV_PY): $(UV)
	UV_CACHE_DIR=$(CURDIR)/$(TOOLS_DIR)/uv-cache UV_PYTHON_INSTALL_DIR=$(CURDIR)/$(TOOLS_DIR)/python \
		$(UV) python install $(PYTHON_VERSION)
	UV_CACHE_DIR=$(CURDIR)/$(TOOLS_DIR)/uv-cache UV_PYTHON_INSTALL_DIR=$(CURDIR)/$(TOOLS_DIR)/python \
		$(UV) venv --python $(PYTHON_VERSION) --python-preference only-managed $(VENV)
	$@ --version && touch $@

ffmpeg: ## ffmpeg + ffprobe: the system's if present, else a pinned static build into .tools/bin (no Homebrew needed)
	@if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then \
		echo ">> ffmpeg: $$(command -v ffmpeg)"; \
	else $(MAKE) --no-print-directory $(TOOLS_BIN)/ffmpeg $(TOOLS_BIN)/ffprobe; fi

$(TOOLS_BIN)/ffmpeg $(TOOLS_BIN)/ffprobe:
	@echo ">> Downloading $(notdir $@) (static build for $(HOST_NAME))"
	mkdir -p $(DOWNLOADS) $(TOOLS_BIN)
	curl -fsSL --retry 3 -o $(DOWNLOADS)/$(notdir $@).zip $(FFMPEG_BASE)/$(FFMPEG_DIR)/$(notdir $@).zip
	cd $(DOWNLOADS) && echo "$(if $(filter ffmpeg,$(notdir $@)),$(FFMPEG_SHA),$(FFPROBE_SHA))  $(notdir $@).zip" | shasum -a 256 -c -
	unzip -o -q $(CURDIR)/$(DOWNLOADS)/$(notdir $@).zip $(notdir $@) -d $(TOOLS_BIN)
	chmod +x $@ && rm -f $(DOWNLOADS)/$(notdir $@).zip
	$@ -version | head -1

doctor: ## Report toolchain health: Godot, templates, Python, browser, display, API keys (present or not, never the value)
	@echo "computer:   $(HOST_NAME), make $(MAKE_VERSION), bash $${BASH_VERSION}"
	@echo "godot:      $$($(GODOT) --version 2>/dev/null || echo 'MISSING: run make bootstrap')"
	@echo "templates:  $$(ls $(TEMPLATES_DIR) 2>/dev/null | grep -v '^\.' | tr '\n' ' ' || echo MISSING)"
	@echo "python:     $$($(PYTHON) --version 2>&1) ($(PYTHON))$(if $(wildcard $(VENV_PY)),, NOT the project's own: make python)"
	@echo "ffmpeg:     $$(ffmpeg -version 2>/dev/null | head -1 | cut -d' ' -f3 || echo 'MISSING (audio tools need it: make ffmpeg)') $$(command -v ffmpeg 2>/dev/null)"
	@echo "git:        $$(git --version 2>/dev/null || echo 'MISSING (Mac: xcode-select --install)')"
	@echo "node:       $$($(NODE) --version 2>/dev/null || echo 'MISSING (only make web-smoke needs it)')"
	@echo "chrome:     $$("$(CHROME)" --version 2>/dev/null || echo 'MISSING (only make web-smoke needs it; set CHROME=...)')"
	@echo "display:    $(if $(filter mac,$(HOST_OS)),the Mac's screen,$${DISPLAY:-none (make run / shots need a display; tests and exports do not)})"
	@echo "meshy key:  $$([ -n "$${MESHY_API_KEY:-}" ] && echo set || echo 'NOT SET (3D models; see _agents/assets.md)')"
	@echo "11labs key: $$([ -n "$${ELEVENLABS_API_KEY:-}" ] && echo set || echo 'NOT SET (sounds and voices; see _agents/audio.md)')"
	@echo "gh:         $$($(GH) --version 2>/dev/null | head -1 || echo 'MISSING (make gh: needed to back up to GitHub)')"
	@echo "git remotes: $$(git remote -v | awk '$$3=="(fetch)"{printf "%s=%s  ", $$1, $$2}')"

# Rebuilds .godot/ (asset imports + the class_name cache). A new `class_name` is invisible to headless runs until
# this has run, so every target that runs project code depends on it.
import: $(GODOT)
	@mkdir -p $(BUILD_DIR) && touch $(BUILD_DIR)/.gdignore
	@$(LOCK) $(GODOT) --headless --path . --import > $(BUILD_DIR)/import.log 2>&1 || { cat $(BUILD_DIR)/import.log; exit 1; }
	@if grep -E '^(ERROR|SCRIPT ERROR)' $(BUILD_DIR)/import.log; then echo ">> import logged errors (above)"; exit 1; fi

# ---- Lint and tests -----------------------------------------------------------

lint: import ## Parse-check every GDScript file (and prove the checker can still SEE an error)
	@$(LOCK) $(GODOT) --headless --path . --script res://tools/lint.gd 2> $(BUILD_DIR)/lint.stderr | grep -v "^Godot Engine" ; s=$${PIPESTATUS[0]}; [ $$s -eq 0 ] || echo "(engine output: $(BUILD_DIR)/lint.stderr)"; exit $$s

test: import ## Run the headless test suite (FILTER=word runs tests whose file::method contains it; a|b = either)
	$(LOCK) $(GODOT) --headless --path . --script res://tests/run_tests.gd -- '--filter=$(FILTER)'

py-test: ## The Python tools' own tests (asset + audio pipelines against mock servers, no network, no credits)
	@n=0; for d in tools/*/; do \
		ls $$d/test_*.py >/dev/null 2>&1 || continue; n=$$((n+1)); \
		echo ">> py-test: $$d"; $(PYTHON) -m unittest discover -s $$d -p 'test_*.py' || exit 1; \
	done; [ $$n -gt 0 ] || { echo "py-test FAILED: found no tools/*/test_*.py at all"; exit 1; }

# ---- The check (see _agents/verification.md) -------------------------------------
# `make check` is what "done" means. It stops at the first red target. Read the LAST lines:
# `>> check: ALL GREEN` or `>> check: FAILED at <target>`. Never read an exit code through a pipe.
CHECK_TARGETS := lint test py-test assets-check audio-check export-web

check: ## Everything headless: lint, tests, tool tests, asset + audio contracts, the web export
	@for t in $(CHECK_TARGETS); do \
		echo ""; echo ">> check: $$t"; \
		$(MAKE) --no-print-directory $$t || { echo ""; echo ">> check: FAILED at $$t"; exit 1; }; \
	done; echo ""; echo ">> check: ALL GREEN ($(CHECK_TARGETS))"

check-all: ## check, then the things that need a display or a browser: shots + web-smoke (each reported)
	@$(MAKE) --no-print-directory check
	@s=0; for t in shots web-smoke; do \
		echo ""; echo ">> check-all: $$t"; \
		$(MAKE) --no-print-directory $$t || { echo ">> check-all: $$t FAILED"; s=1; }; \
	done; [ $$s -eq 0 ] && echo ">> check-all: ALL GREEN" || { echo ">> check-all: FAILED (above)"; exit 1; }

clean: ## Remove build outputs and Godot's import cache
	rm -rf $(BUILD_DIR) .godot

distclean: clean ## Also remove the downloaded toolchain
	rm -rf $(TOOLS_DIR)
