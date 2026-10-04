# Playing the game, looking at it, and adding levels.

.PHONY: editor run play-new demo shot shots new-level

# Optional: LEVEL=hilltop starts there, SPAWN=<marker name>.
_START := $(if $(LEVEL),--level=$(LEVEL)) $(if $(SPAWN),--spawn=$(SPAWN))

editor: $(GODOT) ## Open the Godot editor on this project
	$(GODOT) --path . --editor

run: import ## Play the game (continues your save; LEVEL=id to start somewhere)
	$(GODOT) --path . -- $(_START)

play-new: import ## Play from the very beginning (ignores the save; doesn't overwrite it)
	$(GODOT) --path . -- --new --no-save $(_START)

demo: import ## Watch the player walk around by itself (autopilot), nothing saved
	$(GODOT) --path . -- --new --no-save --autopilot $(_START)

# Screenshots are how Claude SEES the game. Look at every one you make (Read the PNG) before calling work done.
SHOT_DELAY ?= 4
shot: import ## Screenshot one level: LEVEL=id [SHOT_DELAY=4 AUTOPILOT=1] -> build/screenshots/<level>.png (needs a display)
	@mkdir -p $(BUILD_DIR)/screenshots
	@tools/run_strict.sh $(BUILD_DIR)/screenshots/$(or $(LEVEL),start).log \
		timeout 60 $(GODOT) --path . --resolution 1280x720 -- --new --no-save $(_START) $(if $(AUTOPILOT),--autopilot) \
		--screenshot=$(CURDIR)/$(BUILD_DIR)/screenshots/$(or $(LEVEL),start).png --screenshot-delay=$(SHOT_DELAY)

shots: import ## Screenshot EVERY level + 12 s of autopilot -> build/screenshots/*.png; fails on any runtime error (needs a display)
	@mkdir -p $(BUILD_DIR)/screenshots
	@for id in $$($(PYTHON) -c "import json; print(' '.join(json.load(open('data/levels.json'))['levels']))"); do \
		tools/run_strict.sh $(BUILD_DIR)/screenshots/$$id.log timeout 60 $(GODOT) --path . --resolution 1280x720 -- \
			--new --no-save --level=$$id --screenshot=$(CURDIR)/$(BUILD_DIR)/screenshots/$$id.png \
			--screenshot-delay=$(SHOT_DELAY) || exit 1; \
	done
	@# The autopilot playing the start level: catches errors that only happen when things get picked up and freed.
	@tools/run_strict.sh $(BUILD_DIR)/screenshots/autopilot.log timeout 60 $(GODOT) --path . --resolution 1280x720 -- \
		--new --no-save --autopilot --screenshot=$(CURDIR)/$(BUILD_DIR)/screenshots/autopilot.png --screenshot-delay=12

new-level: ## Add a level from the template: ID=lava_fields TITLE="Lava Fields" [MUSIC=explore]
	@test -n "$(ID)" || { echo 'usage: make new-level ID=lava_fields TITLE="Lava Fields"'; exit 1; }
	$(PYTHON) tools/new_level.py --id "$(ID)" --title "$(or $(TITLE),$(ID))" --music "$(MUSIC)"
