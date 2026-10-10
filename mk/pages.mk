# Choices pages: the director (you!) taps picks on a page; Claude reads the taps back. See _agents/choices_pages.md.

.PHONY: choices-page choices-apply choices-demo

PAGES_DIR := $(BUILD_DIR)/pages

choices-page: ## Build a tap-to-pick page from build/pages/NAME.spec.json -> build/pages/NAME/index.html (+ publish.json)
	@test -n "$(NAME)" || { echo "need NAME= (the spec is build/pages/NAME.spec.json)"; exit 2; }
	$(PYTHON) tools/pages/choices_page.py $(PAGES_DIR)/$(NAME).spec.json

choices-apply: ## Record the taps: NAME= IN=<the folder (or JSON file) the ArtifactData read saved> -> data/decisions/NAME.json
	@test -n "$(NAME)" || { echo "need NAME="; exit 2; }
	@test -n "$(IN)" || { echo "need IN= (e.g. build/pages/$(NAME)/taps, the out_dir you gave the ArtifactData list)"; exit 2; }
	$(PYTHON) tools/pages/apply_choices.py $(NAME) $(IN)

choices-demo: ## A demo page with placeholder pictures and sounds (every question kind) -> build/pages/demo/index.html
	$(PYTHON) tools/pages/make_demo.py
	$(PYTHON) tools/pages/choices_page.py $(PAGES_DIR)/demo.spec.json

# Headless Chrome (puppeteer-core, installed on first use by the rule in mk/web.mk).
WEB_SMOKE_DIR  ?= tools/web_smoke
WEB_SMOKE_DEPS ?= $(WEB_SMOKE_DIR)/node_modules/.package-lock.json

.PHONY: choices-shot
choices-shot: $(WEB_SMOKE_DEPS) ## Look before you publish: phone + desktop screenshots of build/pages/NAME/ (TAP=1 also taps and checks saving)
	@test -n "$(NAME)" || { echo "need NAME="; exit 2; }
	CHROME="$(CHROME)" $(NODE) $(WEB_SMOKE_DIR)/page_shot.mjs $(PAGES_DIR)/$(NAME)/index.html $(BUILD_DIR)/screenshots/pages/$(NAME) $(if $(TAP),--tap)
