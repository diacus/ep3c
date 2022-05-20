help: ## Display this help section
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-38s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

install: ## Installs this configuration
	install -d $(HOME)/.config/emacs
	install -d $(HOME)/.emacs.d
	install src/emacs.org src/custom.el $(HOME)/.config/emacs
	install src/init.el $(HOME)/.emacs.d

sync: ## Copies any change made on the installed configuration
	@cp -f $(HOME)/.emacs.d/init.el src/
	@cp -f $(HOME)/.config/emacs/custom.el src/
	@cp -f $(HOME)/.config/emacs/emacs.org src/

reset-emacs: ## Removes all the configuration for emacs
	@rm -rf $(HOME)/.emacs.d
	@rm -rf $(HOME)/.config/emacs

.PHONY: help install sync reset-emacs
