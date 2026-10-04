# Toolchain, lint, tests, the check, cleanup.

.PHONY: bootstrap doctor import lint test py-test check check-all clean distclean

# ---- Bootstrap ----------------------------------------------------------------

bootstrap: $(GODOT) $(TEMPLATES_OK) import doctor ## Install pinned Godot + export templates into ./.tools, import the project

$(DOWNLOADS)/SHA512-SUMS.txt:
	mkdir -p $(DOWNLOADS)
	curl -fsSL --retry 3 -o $@ $(RELEASE_URL)/SHA512-SUMS.txt

$(GODOT): $(DOWNLOADS)/SHA512-SUMS.txt
	@echo ">> Downloading Godot $(GODOT_TAG) editor"
	curl -fL --retry 3 -C - -o $(DOWNLOADS)/$(EDITOR_ZIP) $(RELEASE_URL)/$(EDITOR_ZIP)
	cd $(DOWNLOADS) && grep " $(EDITOR_ZIP)$$" SHA512-SUMS.txt | sha512sum -c -
	mkdir -p $(GODOT_HOME)
	unzip -o -q $(DOWNLOADS)/$(EDITOR_ZIP) -d $(GODOT_HOME)
	touch $(GODOT_HOME)/._sc_
	rm -f $(DOWNLOADS)/$(EDITOR_ZIP)
	touch $@

$(TEMPLATES_OK): $(DOWNLOADS)/SHA512-SUMS.txt
	@echo ">> Downloading Godot $(GODOT_TAG) export templates (~1.3 GB, trimmed after extraction)"
	curl -fL --retry 3 -C - -o $(DOWNLOADS)/$(TEMPLATES_TPZ) $(RELEASE_URL)/$(TEMPLATES_TPZ)
	cd $(DOWNLOADS) && grep " $(TEMPLATES_TPZ)$$" SHA512-SUMS.txt | sha512sum -c -
	mkdir -p $(TEMPLATES_DIR)
	unzip -j -o -q $(DOWNLOADS)/$(TEMPLATES_TPZ) $(addprefix templates/,$(TEMPLATE_FILES)) -d $(TEMPLATES_DIR)
	chmod +x $(TEMPLATES_DIR)/linux_*.x86_64
	rm -f $(DOWNLOADS)/$(TEMPLATES_TPZ)
	touch $@

doctor: ## Report toolchain health: Godot, templates, Python, browser, display, API keys (present or not, never the value)
	@echo "godot:      $$($(GODOT) --version 2>/dev/null || echo 'MISSING: run make bootstrap')"
	@echo "templates:  $$(ls $(TEMPLATES_DIR) 2>/dev/null | grep -v '^\.' | tr '\n' ' ' || echo MISSING)"
	@echo "python:     $$($(PYTHON) --version 2>&1)"
	@echo "ffmpeg:     $$(ffmpeg -version 2>/dev/null | head -1 | cut -d' ' -f3 || echo 'MISSING (audio tools need it: sudo apt install ffmpeg)')"
	@echo "node:       $$($(NODE) --version 2>/dev/null || echo 'MISSING (only make web-smoke needs it)')"
	@echo "chrome:     $$($(CHROME) --version 2>/dev/null || echo 'MISSING (only make web-smoke needs it; set CHROME=...)')"
	@echo "display:    $${DISPLAY:-none (make run / shots need a display; tests and exports do not)}"
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
