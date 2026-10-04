# Sharing the game: the browser build, the desktop build, and putting it online. See _agents/sharing.md.

.PHONY: export-web serve-web web-smoke export-desktop publish-web web-zip

WEB_SMOKE_DIR  ?= tools/web_smoke
WEB_SMOKE_DEPS ?= $(WEB_SMOKE_DIR)/node_modules/.package-lock.json
SMOKE_PORT     ?= 8061
WEB_DIR        := $(BUILD_DIR)/web
DESKTOP_DIR    := $(BUILD_DIR)/desktop
# GitHub Pages refuses any single file over 100 MB (and warns from 50 MB); Cloudflare Pages stops at 25 MiB a file.
WEB_FILE_WARN_MB ?= 80

export-web: import $(TEMPLATES_OK) ## Export the browser build to build/web (single-threaded: runs on any static host) and report its size
	@rm -rf $(WEB_DIR) && mkdir -p $(WEB_DIR)
	@$(LOCK) $(GODOT) --headless --path . --export-release "Web" $(WEB_DIR)/index.html > $(BUILD_DIR)/export-web.log 2>&1 \
		|| { cat $(BUILD_DIR)/export-web.log; echo ">> export-web FAILED (log above: $(BUILD_DIR)/export-web.log)"; exit 1; }
	@test -s $(WEB_DIR)/index.pck && test -s $(WEB_DIR)/index.wasm \
		|| { cat $(BUILD_DIR)/export-web.log; echo ">> export-web FAILED: no index.pck / index.wasm in $(WEB_DIR)"; exit 1; }
	@grep -E '^(ERROR|SCRIPT ERROR)' $(BUILD_DIR)/export-web.log | sed 's/^/>> export-web log: /' || true
	@$(MAKE) --no-print-directory _web-size

# Sizes, biggest first, and a warning for any file a free host would refuse.
_web-size:
	@echo ">> web build: $$(du -sh $(WEB_DIR) | cut -f1) in $(WEB_DIR) (game data index.pck: $$(du -h $(WEB_DIR)/index.pck | cut -f1), engine index.wasm: $$(du -h $(WEB_DIR)/index.wasm | cut -f1))"
	@find $(WEB_DIR) -type f -size +$(WEB_FILE_WARN_MB)M -printf '%s %p\n' | while read -r bytes path; do \
		echo ">> WARNING: $$path is $$((bytes / 1000000)) MB. GitHub Pages refuses files over 100 MB (see _agents/sharing.md: shrink textures/audio)"; done
	@find $(WEB_DIR) -type f -size +25M -size -$(WEB_FILE_WARN_MB)M -printf '>> note: %p is over 25 MiB: fine for GitHub Pages and itch.io, too big for Cloudflare Pages\n'

serve-web: export-web ## Play the browser build at http://localhost:8060 (WEB_HOST=0.0.0.0: other devices at home can play too)
	$(PYTHON) tools/serve_web.py $(WEB_DIR) $(WEB_PORT) $(WEB_HOST)

web-smoke: export-web $(WEB_SMOKE_DEPS) ## Boot the browser build in headless Chrome: no errors, the game draws -> build/web-smoke.png
	@$(PYTHON) tools/serve_web.py $(WEB_DIR) $(SMOKE_PORT) 127.0.0.1 >/dev/null 2>&1 & server=$$!; \
	trap 'kill $$server 2>/dev/null' EXIT; \
	CHROME=$(CHROME) $(NODE) $(WEB_SMOKE_DIR)/smoke.mjs "http://127.0.0.1:$(SMOKE_PORT)/" $(CURDIR)/$(BUILD_DIR)/web-smoke.png

$(WEB_SMOKE_DEPS): $(WEB_SMOKE_DIR)/package.json
	@command -v $(NODE) >/dev/null || { echo "need Node.js for browser checks (https://nodejs.org, or: sudo apt install nodejs npm)"; exit 1; }
	cd $(WEB_SMOKE_DIR) && $(NPM) install --no-audit --no-fund
	touch $@

export-desktop: import $(TEMPLATES_OK) ## Export the Linux desktop game to build/desktop (one file) + a zip to share
	@rm -rf $(DESKTOP_DIR) && mkdir -p $(DESKTOP_DIR)
	@$(LOCK) $(GODOT) --headless --path . --export-release "Linux Desktop" $(DESKTOP_DIR)/game.x86_64 > $(BUILD_DIR)/export-desktop.log 2>&1 \
		|| { cat $(BUILD_DIR)/export-desktop.log; echo ">> export-desktop FAILED"; exit 1; }
	@test -x $(DESKTOP_DIR)/game.x86_64 || { cat $(BUILD_DIR)/export-desktop.log; echo ">> export-desktop FAILED: no game.x86_64"; exit 1; }
	@cd $(DESKTOP_DIR) && rm -f game-linux.zip && $(PYTHON) -m zipfile -c game-linux.zip game.x86_64
	@echo ">> desktop build: $(DESKTOP_DIR)/game.x86_64 ($$(du -h $(DESKTOP_DIR)/game.x86_64 | cut -f1)); to share: $(DESKTOP_DIR)/game-linux.zip"

web-zip: export-web ## Zip the browser build for itch.io (upload as "HTML", played in the browser) -> build/game-web.zip
	@rm -f $(BUILD_DIR)/game-web.zip && cd $(WEB_DIR) && $(PYTHON) -m zipfile -c ../game-web.zip $$(ls)
	@echo ">> $(BUILD_DIR)/game-web.zip ($$(du -h $(BUILD_DIR)/game-web.zip | cut -f1)): upload it on itch.io (see _agents/sharing.md)"

# GitHub Pages: the build goes to the `gh-pages` branch of your GitHub repo (a separate branch holding only the game
# files; your code's branches are untouched). The first time, also turn Pages on (sharing.md has the clicks).
publish-web: export-web ## Put the browser build online with GitHub Pages so friends can play (pushes branch gh-pages)
	@url=$$(git remote get-url origin 2>/dev/null) || { echo ">> publish-web: this repo has no GitHub remote yet. See _agents/sharing.md (Put it online)."; exit 1; }; \
	case "$$url" in *github.com*) ;; *) echo ">> publish-web: origin is not GitHub ($$url). See _agents/sharing.md."; exit 1;; esac; \
	slug=$$(echo "$$url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$$##'); \
	owner=$${slug%%/*}; repo=$${slug#*/}; \
	out=$(BUILD_DIR)/gh-pages; rm -rf $$out; cp -r $(WEB_DIR) $$out; touch $$out/.nojekyll; \
	( cd $$out && git init -q -b gh-pages && git add -A && \
	  git -c user.name="$$(git -C $(CURDIR) config user.name || echo game)" -c user.email="$$(git -C $(CURDIR) config user.email || echo game@localhost)" \
	      commit -q -m "Publish the web build ($$(git -C $(CURDIR) rev-parse --short HEAD 2>/dev/null || echo uncommitted))" && \
	  git push -q -f "$$url" gh-pages ) || { echo ">> publish-web FAILED: the push was refused (signed in to GitHub? see _agents/sharing.md)"; exit 1; }; \
	if command -v gh >/dev/null; then \
		gh api -X POST "repos/$$slug/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null 2>&1 \
			&& echo ">> GitHub Pages switched on for $$slug" || true; \
	fi; \
	echo ">> published. In a minute or two, friends can play at: https://$$owner.github.io/$$repo/"; \
	echo "   (first time? check Settings > Pages on GitHub says: Deploy from a branch, gh-pages, / (root))"
