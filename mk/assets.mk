# 3D models: Meshy concept pictures → the kid picks → image-to-3D → fitted into a visual slot. _agents/assets.md.
# The kid's agent follows .claude/skills/make-model/SKILL.md. Every Godot run goes through $(LOCK).

.PHONY: assets-slots art-concept art-choices art-decide art-status model-generate model-from-text model-fit \
	assets-normalize assets-inspect assets-textures assets-check model-look model-look-raw assets-gallery \
	assets-mock meshy-balance

ASSETS_PIPELINE := $(LOCK) $(GODOT) --headless --path . --script res://assets/pipeline/pipeline.gd --
ASSETS_PY       := $(PYTHON) tools/assets
# Hide Godot's banner but keep its exit code (bash pipefail: the pipeline fails when Godot does).
ASSETS_QUIET    := { grep -vE '^Godot Engine|^$$' || true; }
SHOTS_DIR       := $(BUILD_DIR)/screenshots
LOOK_SIZE       ?= 1280x720

# ---- The slots (data/slots.json) ----------------------------------------------------------------------------------

assets-slots: import ## List every visual slot: size, triangle budget, fit, and whether it has a model yet
	@$(ASSETS_PIPELINE) slots 2>&1 | $(ASSETS_QUIET)

# ---- Pictures first: the kid picks before anything is built in 3D ---------------------------------------------------

art-concept: ## A concept picture (≈9 credits): SLOT=player PROMPT="a knight made of toast" [NAME=player_a TITLE="Toast knight" NOTE="tradeoff" REFS="a.png b.png" KEEP_BG=1]
	@test -n "$(SLOT)" -a -n "$(PROMPT)" || { echo "need SLOT= and PROMPT= (make assets-slots lists the slots)"; exit 2; }
	$(ASSETS_PY)/generate.py concept --slot "$(SLOT)" --prompt "$(PROMPT)" $(if $(NAME),--id "$(NAME)") \
		$(if $(TITLE),--title "$(TITLE)") $(if $(NOTE),--note "$(NOTE)") $(foreach r,$(REFS),--reference "$(r)") \
		$(if $(KEEP_BG),--keep-background)

art-choices: ## Write the tap-to-pick page spec for every waiting picture: NAME=models-1 [TITLE= SLOTS="player prop_rock"] → build/pages/NAME.spec.json
	@test -n "$(NAME)" || { echo "need NAME= (a short page name like models-1)"; exit 2; }
	$(ASSETS_PY)/review.py choices --name "$(NAME)" $(if $(TITLE),--title "$(TITLE)") $(foreach s,$(SLOTS),--slot "$(s)")

art-decide: ## Record the kid's picks: NAME=models-1 (reads data/decisions/NAME.json), or ID=player_b DECISION=approved|rejected WORDS="their words"
	@if [ -n "$(NAME)" ]; then $(ASSETS_PY)/review.py apply --name "$(NAME)"; \
	elif [ -n "$(ID)" ]; then $(ASSETS_PY)/review.py decide "$(ID)" "$(or $(DECISION),approved)" --words "$(WORDS)"; \
	else echo "need NAME=<page> or ID=<concept> DECISION= WORDS="; exit 2; fi

art-status: ## Every concept picture (waiting / approved / rejected), the kid's words, and the credits spent
	@$(ASSETS_PY)/review.py status

# ---- 3D -----------------------------------------------------------------------------------------------------------

model-generate: ## The picked picture → a 3D model (≈15 credits; QUALITY=high ≈30): SLOT=player or ID=player_b [RETRY="why"]
	@test -n "$(SLOT)$(ID)" || { echo "need SLOT= (its newest picked picture) or ID="; exit 2; }
	$(ASSETS_PY)/generate.py model $(if $(SLOT),--slot "$(SLOT)") $(if $(ID),--id "$(ID)") \
		$(if $(RETRY),--retry "$(RETRY)") $(if $(QUALITY),--quality "$(QUALITY)")

model-from-text: ## Text-to-3D with no picture first (≈30 credits; experiments only): SLOT= PROMPT= [NAME=]
	@test -n "$(SLOT)" -a -n "$(PROMPT)" || { echo "need SLOT= and PROMPT="; exit 2; }
	$(ASSETS_PY)/generate.py text3d --slot "$(SLOT)" --prompt "$(PROMPT)" $(if $(NAME),--name "$(NAME)")

# Fit: size, feet on the ground, facing −Z, triangle budget, web textures → assets/models/<SLOT>.glb, then import it.
# FORWARD is the way the DOWNLOAD faces (look first: make model-look-raw); GLOW=1 uses Meshy's glow map (GLOW=3: brighter).
model-fit: import ## Fit the newest download for a slot into it: SLOT=player [IN=assets/incoming/x.glb FORWARD=+z UP=+y TURN=0 GLOW=1]
	@test -n "$(SLOT)" || { echo "need SLOT= (and IN= if it wasn't made with make model-generate)"; exit 2; }
	@in="$(IN)"; [ -n "$$in" ] || in=$$($(ASSETS_PY)/review.py model-file --slot "$(SLOT)") || exit 1; \
	echo ">> fitting $$in into slot $(SLOT)"; \
	$(ASSETS_PIPELINE) normalize --in="$$in" --slot="$(SLOT)" $(if $(FORWARD),--forward=$(FORWARD)) $(if $(UP),--up=$(UP)) \
		$(if $(TURN),--turn=$(TURN)) $(if $(GLOW),--glow=$(if $(filter 1,$(GLOW)),2,$(GLOW))) 2>&1 | $(ASSETS_QUIET) \
		|| { echo ">> model-fit FAILED (above)"; exit 1; }
	@$(LOCK) $(GODOT) --headless --path . --import > $(BUILD_DIR)/import.log 2>&1 || { cat $(BUILD_DIR)/import.log; exit 1; }
	@echo ">> assets/models/$(SLOT).glb is in the game. Look at it: make model-look SLOT=$(SLOT)"

assets-normalize: ## Same as model-fit, with the input named: IN=path.glb SLOT=player [FORWARD= UP= TURN= GLOW=]
	@test -n "$(IN)" -a -n "$(SLOT)" || { echo "need IN= and SLOT="; exit 2; }
	@$(MAKE) --no-print-directory model-fit IN="$(IN)" SLOT="$(SLOT)"

assets-inspect: import ## Measure a model (size, triangles, materials, textures): IN=path.glb [SLOT= to check it against the slot]
	@test -n "$(IN)" || { echo "need IN="; exit 2; }
	@$(ASSETS_PIPELINE) inspect --in="$(IN)" $(if $(SLOT),--slot=$(SLOT)) 2>&1 | $(ASSETS_QUIET)

assets-textures: ## Give every model's .import the web texture policy (Basis Universal inside the GLB), then import
	@$(ASSETS_PIPELINE) textures 2>&1 | $(ASSETS_QUIET)
	@$(LOCK) $(GODOT) --headless --path . --import > $(BUILD_DIR)/import.log 2>&1 || { cat $(BUILD_DIR)/import.log; exit 1; }

# Part of `make check`. Passes on an empty assets/models/ (every slot shows its placeholder).
assets-check: import ## Every model in assets/models/ meets its slot: size, feet on the ground, triangle budget, textures
	@$(ASSETS_PIPELINE) check 2>&1 | $(ASSETS_QUIET)

# ---- Looking at models (need a display) ---------------------------------------------------------------------------

model-look: import ## Four-side picture of a slot's finished model in its slot box, with a FRONT arrow and a 1.7 m person: SLOT=player → build/screenshots/look-SLOT.png
	@test -n "$(SLOT)" || { echo "need SLOT="; exit 2; }
	@[ -n "$${DISPLAY:-}" ] || { echo "model-look needs a display (DISPLAY is not set)"; exit 2; }
	@mkdir -p $(SHOTS_DIR)
	@$(LOCK) timeout 120 $(GODOT) --path . --resolution $(LOOK_SIZE) --script res://assets/pipeline/model_look.gd -- \
		--slot=$(SLOT) --out=$(CURDIR)/$(SHOTS_DIR)/look-$(SLOT).png 2>&1 | { grep -E 'MODEL_LOOK|note:' || true; }

model-look-raw: import ## Four-side picture of a raw download with its +X/+Z axes, to choose FORWARD= for model-fit: IN=path.glb
	@test -n "$(IN)" || { echo "need IN="; exit 2; }
	@[ -n "$${DISPLAY:-}" ] || { echo "model-look-raw needs a display (DISPLAY is not set)"; exit 2; }
	@mkdir -p $(SHOTS_DIR)
	@$(LOCK) timeout 120 $(GODOT) --path . --resolution $(LOOK_SIZE) --script res://assets/pipeline/model_look.gd -- \
		--in=$(IN) --out=$(CURDIR)/$(SHOTS_DIR)/look-raw-$(basename $(notdir $(IN))).png 2>&1 | { grep -E 'MODEL_LOOK|size|triangles' || true; }

assets-gallery: import ## Every slot side by side (its model, or its placeholder), with a 1.7 m person → build/screenshots/assets-gallery.png
	@[ -n "$${DISPLAY:-}" ] || { echo "assets-gallery needs a display (DISPLAY is not set)"; exit 2; }
	@mkdir -p $(SHOTS_DIR)
	@$(LOCK) timeout 120 $(GODOT) --path . --resolution 1600x700 --script res://assets/pipeline/model_look.gd -- \
		--all --out=$(CURDIR)/$(SHOTS_DIR)/assets-gallery.png 2>&1 | { grep -E 'MODEL_LOOK' || true; }

# ---- Practice and money -------------------------------------------------------------------------------------------

assets-mock: ## Serve a pretend Meshy on 127.0.0.1:8799 (no key, no credits); point the tools at it with MESHY_BASE_URL
	$(ASSETS_PY)/mock_provider.py 8799

meshy-balance: ## Credits left on the Meshy account (free), and what this game has spent
	@$(ASSETS_PY)/generate.py balance
