# Starting new games from the foundation, and pulling kit improvements into a game.

.PHONY: new-game foundation-update foundation-selftest

new-game: ## (in game-foundation) Start a kid's game: NAME="Lava Lover" DIR=~/projects/lava-lover DIRECTOR=Sam
	@test -n "$(NAME)" -a -n "$(DIR)" || { echo 'usage: make new-game NAME="Lava Lover" DIR=~/projects/lava-lover DIRECTOR=Sam'; exit 1; }
	tools/new_game.sh "$(NAME)" "$(DIR)" "$(DIRECTOR)"

foundation-update: ## (in a game) Merge the latest kit, tools and docs from the foundation, then run the check
	@git remote get-url foundation >/dev/null 2>&1 || { echo "this repo has no 'foundation' remote (is this the foundation itself?)"; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "commit your work first"; exit 1; }
	git config merge.ours.driver true
	git fetch foundation
	git merge --no-edit foundation/main
	$(MAKE) --no-print-directory check

foundation-selftest: ## (in game-foundation) Make a throwaway game from the last COMMIT and run make check in it: proves a fresh clone works
	@test -z "$$(git status --porcelain)" || { echo "commit first: the selftest clones the last commit, not your working tree"; exit 1; }
	rm -rf $(BUILD_DIR)/selftest
	tools/new_game.sh "Selftest" "$(CURDIR)/$(BUILD_DIR)/selftest" "Selftest"
	$(MAKE) -C $(BUILD_DIR)/selftest --no-print-directory check

kid-setup-command: ## (in game-foundation, YOUR terminal) Print the one-line Mac setup command for a kid, keys included (secret!)
	@tools/kid_setup_command.sh
