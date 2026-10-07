# Minna no Nihongo — dev tasks
PYTHON ?= python3

# The firebase CLI is not on PATH on this machine, so npx fetches it. Override with an
# installed one if you have it: `make rules FIREBASE=/path/to/firebase`.
FIREBASE ?= npx -y firebase-tools
FIREBASE_PROJECT ?= kf-nihongo

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

## rules-check: compile firestore.rules server-side without publishing (dry run)
.PHONY: rules-check
rules-check:
	$(FIREBASE) deploy --only firestore:rules --project $(FIREBASE_PROJECT) --dry-run

## rules: publish firestore.rules to Firebase (scoped — never touches hosting)
#
# `--only firestore:rules` is mandatory, not tidiness: firebase.json declares hosting too,
# so a bare `firebase deploy` would also push whatever is sitting in web/ — generated
# output that may be a stale generation. See .claude/skills/deploy-firestore-rules.
#
# The rules and the app that matches them are one change: an unpublished field or an
# unlisted enum value rejects *every* write to all three survey collections, silently.
.PHONY: rules
rules: rules-check
	$(FIREBASE) deploy --only firestore:rules --project $(FIREBASE_PROJECT)
	@echo "✅ Rules published to $(FIREBASE_PROJECT)."

## help: list available targets
.PHONY: help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
