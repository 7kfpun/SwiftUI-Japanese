#!/bin/sh
# Xcode Cloud runs this after cloning, before resolving packages or building.
# It gives the clean clone what a developer's checkout already has: the bundled
# data generated from the `minna` submodule, and the git-ignored config plists.
set -eu

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO"

echo "== action: ${CI_XCODEBUILD_ACTION:-?}  scheme: ${CI_XCODE_SCHEME:-?}  branch: ${CI_BRANCH:-${CI_PULL_REQUEST_SOURCE_BRANCH:-?}}"

# --- 1. Data submodule ------------------------------------------------------
# Xcode Cloud clones submodules itself once the `minna` repo is granted under
# App Store Connect → Xcode Cloud → Settings → Repositories. The update is a
# fallback; with no access it fails here instead of shipping an empty app.
# The course data sits one level down, at minna/minna/ — the path
# build-minna-data.py reads.
if [ ! -d minna/minna/vocab ]; then
  git submodule update --init minna || true
fi
if [ ! -d minna/minna/vocab ]; then
  echo "error: minna/minna/vocab is missing — grant Xcode Cloud access to 7kfpun/minna." >&2
  git submodule status minna >&2 || true
  ls -la minna >&2 || true
  exit 1
fi

# --- 2. Generated resources -------------------------------------------------
python3 scripts/build-minna-data.py

# --- 3. Secrets -------------------------------------------------------------
# Each is a base64-encoded plist stored as a *secret* environment variable on
# the workflow (`base64 -i file.plist | pbcopy`). Absent means the same as a
# fresh clone: Google test ad units and no Firebase — fine for tests, never
# for an archive that could reach TestFlight.
write_plist() { # $1 = env var name, $2 = destination
  value=$(printenv "$1" || true)
  if [ -n "$value" ]; then
    printf '%s' "$value" | base64 --decode > "$2"
    plutil -lint "$2" >/dev/null
    echo "wrote $2 from \$$1"
  fi
}

write_plist MINNA_SECRETS_PLIST              nihongo/Secrets.plist
write_plist MINNA_GOOGLE_SERVICE_INFO_PLIST  nihongo/GoogleService-Info.plist

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
  for f in nihongo/Secrets.plist nihongo/GoogleService-Info.plist; do
    if [ ! -f "$f" ]; then
      echo "error: archiving without $f would ship test ad units / no Firebase. Set the workflow's secret env vars." >&2
      exit 1
    fi
  done
fi

echo "== post-clone done"
