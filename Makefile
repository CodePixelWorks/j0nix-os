# j0nix-os — quick repo actions
#
# Run `make` or `make help` to see available targets.
# Install the pre-commit hook with: make install-hooks

.PHONY: help check build switch readme readme-public readme-private check-readme install-hooks

HOST ?= Jonas-PC
SCOPE ?= private

help: ## Show this help
	@echo "j0nix-os quick actions"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  HOST=<name>    Target host for build/switch (default: $(HOST))"
	@echo "  SCOPE=<scope>  Scope for README regeneration (default: $(SCOPE))"

check: ## Validate flake (fast, no build)
	nix flake check --no-build

build: ## Build current host (no switch)
	sudo nixos-rebuild build --flake .#$(HOST)

switch: ## Build and switch current host
	sudo nixos-rebuild switch --flake .#$(HOST)

readme: readme-$(SCOPE) ## Regenerate README (default scope: $(SCOPE))

readme-public: ## Regenerate README for public mirror scope
	python3 scripts/regenerate-readme.py --scope public --output README.md

readme-private: ## Regenerate README for private source scope
	python3 scripts/regenerate-readme.py --scope private --output README.md

check-readme: ## Fail if README is out of date (CI mode)
	python3 scripts/regenerate-readme.py --scope $(SCOPE) --check

install-hooks: ## Install git pre-commit hook
	@mkdir -p .git/hooks
	@cp scripts/git-hooks/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "Installed .git/hooks/pre-commit"
