# Git and GitHub: Claude runs these for the kid (see _agents/git.md and the setup-my-game skill).

.PHONY: gh start-my-game github-status github-login github-create backup sync

gh: $(GH) ## Install GitHub's command-line tool into .tools (no sudo needed)

$(GH):
	@echo ">> Downloading gh $(GH_VERSION) for $(HOST_NAME)"
	mkdir -p $(DOWNLOADS) $(GH_HOME)
	curl -fsSL --retry 3 -o $(DOWNLOADS)/$(GH_ARCHIVE) $(GH_URL)/$(GH_ARCHIVE)
	curl -fsSL --retry 3 -o $(DOWNLOADS)/gh_$(GH_VERSION)_checksums.txt $(GH_URL)/gh_$(GH_VERSION)_checksums.txt
	cd $(DOWNLOADS) && grep " $(GH_ARCHIVE)$$" gh_$(GH_VERSION)_checksums.txt | shasum -a 256 -c -
ifeq ($(HOST_OS),mac)
	rm -rf $(DOWNLOADS)/gh-unzip && mkdir -p $(DOWNLOADS)/gh-unzip
	unzip -q -o $(DOWNLOADS)/$(GH_ARCHIVE) -d $(DOWNLOADS)/gh-unzip
	cp -R $(DOWNLOADS)/gh-unzip/$(basename $(GH_ARCHIVE))/. $(GH_HOME)/
	rm -rf $(DOWNLOADS)/gh-unzip
else
	tar -xzf $(DOWNLOADS)/$(GH_ARCHIVE) -C $(GH_HOME) --strip-components=1
endif
	rm -f $(DOWNLOADS)/$(GH_ARCHIVE)
	test -x $@ && touch $@

start-my-game: ## First-time setup in a fresh clone of the foundation: NAME="Lava Lover" DIRECTOR=Sam (makes it YOUR game)
	@test -n "$(NAME)" || { echo 'usage: make start-my-game NAME="Lava Lover" DIRECTOR=Sam'; exit 1; }
	tools/start_my_game.sh "$(NAME)" "$(DIRECTOR)"

github-status: $(GH) ## Is this game signed in to GitHub, and does it have its own GitHub repo? (one line each)
	@tools/github.sh status

github-login: $(GH) ## Sign this game in to the kid's GitHub account: prints a code to type at github.com/login/device
	@tools/github.sh login

github-create: $(GH) ## Make the kid's own PRIVATE GitHub repo for this game and back it up there: REPO=lava-lover
	@test -n "$(REPO)" || { echo 'usage: make github-create REPO=lava-lover'; exit 1; }
	@tools/github.sh create "$(REPO)"

backup: $(GH) ## Back up the game to GitHub (push the committed work to origin)
	@tools/github.sh backup

sync: $(GH) ## Get the latest from GitHub first (if the game was worked on from another computer)
	@tools/github.sh sync
