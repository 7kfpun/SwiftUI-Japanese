# Minna no Nihongo — dev tasks
PYTHON ?= python3

.DEFAULT_GOAL := setup

## setup: first-time setup — fetch the vocab submodule and build bundled data
.PHONY: setup
setup: submodule data
	@echo "✅ Ready. Open nihongo.xcodeproj and Run."

## submodule: init/update the `minna` data submodule (pinned commit)
.PHONY: submodule
submodule:
	git submodule update --init minna

## refresh: pull the latest `minna` and rebuild bundled data
.PHONY: refresh
refresh:
	git submodule update --init --remote minna
	$(MAKE) data
	@echo "✅ Data refreshed from latest minna."

## data: (re)generate nihongo/Resources/MinnaData.json + flat audio clips from ./minna
.PHONY: data
data:
	$(PYTHON) scripts/build-minna-data.py

## clean: remove generated bundled resources
.PHONY: clean
clean:
	rm -rf nihongo/Resources/audio nihongo/Resources/MinnaData.json

## help: list available targets
.PHONY: help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
