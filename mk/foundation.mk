# Starting new games from the foundation, and pulling kit improvements into a game.

.PHONY: new-game foundation-update

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
