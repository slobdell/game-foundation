# Sound: effects and voices from ElevenLabs, music from Suno, free placeholders, and the audio check.
# How it all fits: _agents/audio.md. The kid's agent's recipe: .claude/skills/make-sound/SKILL.md.
#
# PAID targets (sounds, voices, audio-choices when it needs new takes) print the cost before and after and append to
# assets/audio/elevenlabs_ledger.md. Add MOCK=1 to any of them to use the free pretend server instead (make audio-mock
# in another terminal first), or DRY=1 to see the plan and the price without sending anything.

.PHONY: sounds sounds-placeholders voices voice-list music-import music-check audio-mock audio-choices audio-apply audio-check

AUDIO_MOCK_PORT ?= 8099
AUDIO_URL := $(if $(MOCK),--base-url http://127.0.0.1:$(AUDIO_MOCK_PORT))

sounds: ## PAID: make real sound effects (ElevenLabs) for every sound in assets/audio/sounds.json that has none [ONLY=a,b FORCE=1 DRY=1 MOCK=1]
	$(PYTHON) tools/audio/sfx.py $(if $(ONLY),--only $(ONLY)) $(if $(FORCE),--force) $(if $(DRY),--dry-run) $(AUDIO_URL) $(if $(NOTE),--note "$(NOTE)")

sounds-placeholders: ## Free stand-in sounds (beeps, whooshes) for every sound with no files yet, and the "explore" music loop [ONLY=a,b]
	$(PYTHON) tools/audio/placeholders.py --music $(if $(ONLY),--only $(ONLY))

voices: ## PAID: record every dialogue line that has a "voice" id but no clip (or changed text) [ONLY=line_ids FORCE=1 DRY=1 MOCK=1]
	$(PYTHON) tools/audio/voices.py $(if $(ONLY),--only $(ONLY)) $(if $(FORCE),--force) $(if $(DRY),--dry-run) $(AUDIO_URL) $(if $(NOTE),--note "$(NOTE)")

voice-list: ## The ElevenLabs voices this account can use (free) [SEARCH="british old"]
	$(PYTHON) tools/audio/voices.py --list "$(SEARCH)" $(AUDIO_URL)

music-import: ## Import a Suno download as a looping track: IN=~/Downloads/x.mp3 ID=lava_theme [FROM=0:12 TO=2:05 BPM=100 RIGHTS="Suno Pro, 2026-10-04" TITLE=...]
	@test -n "$(IN)" || { echo "usage: make music-import IN=~/Downloads/<file>.mp3 ID=<track_id> [FROM=0:12 TO=2:05 BPM=100 RIGHTS=...]"; exit 2; }
	@test -n "$(ID)" || { echo "ID is required: the name the game uses, e.g. ID=lava_theme (Sound.music(\"lava_theme\"))"; exit 2; }
	$(PYTHON) tools/audio/music.py import "$(IN)" --id $(ID) $(if $(FROM),--from $(FROM)) $(if $(TO),--to $(TO)) \
		$(if $(BPM),--bpm $(BPM)) $(if $(RIGHTS),--rights "$(RIGHTS)") $(if $(TITLE),--title "$(TITLE)")

music-check: ## Every music track: loudness, peak, a click-free loop, a rights note
	$(PYTHON) tools/audio/music.py check

audio-mock: ## Run the pretend ElevenLabs server (free; Ctrl+C stops). Then add MOCK=1 to sounds / voices / audio-choices
	$(PYTHON) tools/audio/mock_elevenlabs.py --port $(AUDIO_MOCK_PORT)

audio-choices: ## Let the director hear takes and pick (PAID for new takes): NAME=x SOUNDS=a,b | LINES=l1,l2 | SPEAKER=guide VOICES=id1,id2,id3 [TEXT= N= MOCK=1]
	@test -n "$(NAME)" || { echo "NAME is required: a slug for the page, e.g. NAME=footstep_pick"; exit 2; }
	$(PYTHON) tools/audio/choices.py build --name $(NAME) $(if $(SOUNDS),--sounds $(SOUNDS)) $(if $(LINES),--lines $(LINES)) \
		$(if $(SPEAKER),--speaker $(SPEAKER)) $(if $(VOICES),--voices $(VOICES)) $(if $(TEXT),--text "$(TEXT)") \
		$(if $(N),--n $(N)) $(AUDIO_URL) $(if $(NOTE),--note "$(NOTE)")
	@if [ -f tools/pages/choices_page.py ]; then $(MAKE) --no-print-directory choices-page NAME=$(NAME); \
		else echo "(no tools/pages/choices_page.py yet: the spec is build/pages/$(NAME).spec.json)"; fi

audio-apply: ## Put the director's picks into the game: NAME=x (reads data/decisions/NAME.json)
	@test -n "$(NAME)" || { echo "NAME is required (the page's name)"; exit 2; }
	$(PYTHON) tools/audio/choices.py apply --name $(NAME)

audio-check: ## Sounds, voices and music are where they should be and at sane levels (part of make check; must pass on a fresh repo)
	$(PYTHON) tools/audio/check.py
