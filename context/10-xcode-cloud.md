# 10 — Xcode Cloud and GitHub

Xcode Cloud is the CI: it watches the GitHub repo, builds on Apple's Macs, posts
results back to pull requests as GitHub checks, and hands archives to TestFlight.
There is no GitHub Actions workflow — a macOS Actions runner would duplicate the
same build at ten times the minute cost.

Only the `nihongo` app (Minna) is built in the cloud; JLPT is not set up.

Workflows themselves live in App Store Connect, not in the repo. What the repo
carries is `ci_scripts/`, which Xcode Cloud finds by convention next to
`nihongo.xcodeproj`.

## What a clean clone lacks, and how `ci_post_clone.sh` supplies it

| Missing in a clone | Why | Supplied by |
|---|---|---|
| `minna/` | private submodule (`git@github.com:7kfpun/minna.git`) | Xcode Cloud clones it once the repo is granted (below); the script fails loudly if it isn't there |
| `MinnaData.json`, `KanaChart.json`, `audio/` | generated, git-ignored | `scripts/build-minna-data.py` |
| `nihongo/Secrets.plist`, `nihongo/GoogleService-Info.plist` | git-ignored keys | base64 secret env vars on the workflow |

Without the secrets a build behaves like a fresh clone — Google **test** ad units,
Firebase skipped — which is fine for tests. An **archive** without them carries
test ads; for now the script only warns (see TODO), so such a build is fine for
internal TestFlight but must not be submitted to the App Store.

| Env var (mark *Secret*) | Written to |
|---|---|
| `MINNA_SECRETS_PLIST` | `nihongo/Secrets.plist` |
| `MINNA_GOOGLE_SERVICE_INFO_PLIST` | `nihongo/GoogleService-Info.plist` |

Value: `base64 -i nihongo/Secrets.plist | pbcopy`, paste.

## One-time setup

1. **Signing team.** Every target signs with `CC4C8V8BXN`. Xcode Cloud holds one
   team's credentials, so a target on another team fails to sign there.
2. **Connect.** Xcode → *Report navigator* → *Cloud* → *Get Started*, product
   `nihongo`. This installs the Xcode Cloud GitHub App on
   `7kfpun/SwiftUI-Japanese`.
3. **Grant the submodule.** App Store Connect → Xcode Cloud → *Settings* →
   *Repositories* → add `7kfpun/minna`. Without it every build stops at post-clone.
4. **Build number.** Xcode Cloud stamps `CFBundleVersion` with its own counter.
   Set the starting number (Xcode Cloud → *Settings* → *Build Number*) above the
   last uploaded build — the project currently says 26.
5. **Secrets.** Add the env vars above to the archive workflow.

## Suggested workflows

| Workflow | Start condition | Action | Post-action |
|---|---|---|---|
| **PR — tests** | Pull request into `rebuild-swiftui` / `main` | Test, scheme `nihongo`, iPhone 17 Pro, latest iOS 26 | — |
| **TestFlight** | Push to the release branch | Archive iOS, scheme `nihongo` | TestFlight internal testing |

Never add *App Store submission* as a post-action: a submission is confirmed by
a person each time (`CLAUDE.md`). Store metadata stays `fastlane ios metadata`.

Then, in GitHub → branch protection, make the *PR — tests* check required.

## TODO

- [ ] Add `MINNA_SECRETS_PLIST` and `MINNA_GOOGLE_SERVICE_INFO_PLIST` (Secret)
      to the archive workflow.
- [ ] Then turn the archive warning in `ci_post_clone.sh` back into `exit 1`.
- [ ] Turn the workflow on; set Distribution Preparation and a TestFlight
      Internal Testing post-action.
- [ ] Grant `7kfpun/minna` under Xcode Cloud → Settings → Repositories.
- [ ] Set the starting build number above the last upload (26).
- [ ] Add the *PR — tests* workflow and make it a required GitHub check.

## Known gaps

- **UI tests run too.** The `nihongo` scheme's test action includes
  `nihongoUITests`, and Xcode Cloud can't pass `-only-testing`. Add a test plan
  with only `nihongoTests` and select it in the workflow to match `run-tests`.
- **No Crashlytics dSYM upload** exists in any build phase; a
  `ci_scripts/ci_post_xcodebuild.sh` is where it would go.
- **CloudKit schema** still has to be deployed to Production by hand — CI cannot
  do it, and a missed deploy is silent (`CLAUDE.md`, invariants).
