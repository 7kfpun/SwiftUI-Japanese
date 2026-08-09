---
name: push-app-store-metadata
description: Push App Store Connect text metadata (name, subtitle, description, keywords, release notes, promotional text, URLs) from fastlane/metadata/ — including when `fastlane deliver` cannot be used because the version isn't in a state its hardcoded filter recognises, in which case Spaceship::ConnectAPI is driven directly. Use when asked to "push the metadata", "update the App Store description/keywords/release notes", "upload the store text", or when a metadata lane hangs retrying "Cannot find edit app store version" for ten minutes and fails. Also covers why `bundle exec` must be pinned to the system Ruby here, and why `ta` is silently dropped.
when_to_use: push App Store metadata, update the App Store description, upload keywords, release notes, fastlane deliver, fastlane metadata lane, Cannot find edit app store version, deliver retrying with backoff, bundle exec broken, GemNotFound, ta not uploading, App Store Connect localizations
allowed-tools: Bash, Read, Edit
---

# Pushing App Store text metadata

Source of truth is `fastlane/metadata/<locale>/*.txt` — 14 locale folders,
each with `name`, `subtitle`, `description`, `keywords`, `promotional_text`,
`release_notes`, `support_url`, `marketing_url`, `privacy_url`. The lanes live in
`fastlane/Fastfile`; read its header note before anything else, it is current.

**This is an outward-facing write. `CLAUDE.md`: never publish without being
asked.** Editing the `.txt` files is the default deliverable. Stop there.

## Step 0, always: find out what state the version is in

```sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/bundle exec \
  ruby .claude/skills/push-app-store-metadata/asc_state.rb
```

Read-only (GETs only). It prints every version and its `appVersionState`, whether
`get_edit_app_store_version` finds one, and which localizations exist. **Skipping
this step is what costs the twenty minutes below.**

## Trap 1: `bundle exec` is broken under the default Ruby

`ruby` on the PATH is Homebrew's (`/usr/local/Cellar/ruby/4.0.6`, x86_64), but
`vendor/bundle` only contains `ruby/2.6.0` gems — installed for macOS's system
Ruby. A plain `bundle exec` therefore dies with a wall of
`Could not find fastlane-2.230.0, … (Bundler::GemNotFound)`, which reads like a
missing `bundle install` and is not. Don't run `bundle install`; pin the Ruby:

```sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/bundle exec fastlane ios metadata
```

`/usr/bin/bundle` is shebanged to `/System/…/Ruby.framework/Versions/2.6/…/ruby`,
and the stripped PATH keeps Homebrew's `ruby`/`gem` out of the way. `BUNDLE_PATH`
is already `vendor/bundle` via `.bundle/config`, so it needn't be passed.
(`scripts/asc_update_subscriptions.rb`'s header still shows the old
`BUNDLE_PATH=vendor/bundle bundle exec …` form — same fix applies.)

## Trap 2: `deliver` only sees versions in six states

`Deliver::UploadMetadata` calls `app.get_edit_app_store_version`, whose
`appVersionState` filter is hardcoded to exactly:

`PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED`,
`WAITING_FOR_REVIEW`, `INVALID_BINARY`

`READY_FOR_REVIEW` **exists as a constant in the same file and is not in that
list.** So a version sitting in `READY_FOR_REVIEW` — the state between "submit"
and Apple accepting it into the review queue — is invisible to fastlane 2.230.0,
and so are `IN_REVIEW`, `PENDING_APPLE_RELEASE`, `PENDING_DEVELOPER_RELEASE` and
`READY_FOR_DISTRIBUTION`.

When it can't find one, `retry_if_nil` doesn't fail — it **loops**:
`version_check_wait_retry_limit` defaults to 7, sleeping 20s, 40s, 80s, 160s then
capped at 5 minutes, i.e. **up to ~20 minutes** of "Cannot find edit app store
version… Retrying" before it gives up. The lane looks like it's working the whole
time. This is not fixable with a flag; it is the version's state.

So: **the `metadata` and `screenshots` lanes work only when step 0 reports a
non-nil edit version.** It happens to be `WAITING_FOR_REVIEW` today, so they
work today. Re-check every time — this is state, not configuration.

## The fallback: drive Spaceship directly

When step 0 prints `nil`, go around `deliver` and PATCH the localizations on a
version you name yourself. Field split, taken from `Deliver::UploadMetadata`'s own
constants:

| `metadata/<locale>/` file | Object | Attribute |
|---|---|---|
| `description.txt` | `AppStoreVersionLocalization` | `description` |
| `keywords.txt` | `AppStoreVersionLocalization` | `keywords` |
| `release_notes.txt` | `AppStoreVersionLocalization` | `whats_new` |
| `promotional_text.txt` | `AppStoreVersionLocalization` | `promotional_text` |
| `support_url.txt` | `AppStoreVersionLocalization` | `support_url` |
| `marketing_url.txt` | `AppStoreVersionLocalization` | `marketing_url` |
| `name.txt` | `AppInfoLocalization` | `name` |
| `subtitle.txt` | `AppInfoLocalization` | `subtitle` |
| `privacy_url.txt` | `AppInfoLocalization` | `privacy_policy_url` |

Name and subtitle live on the **app info**, not the version — that split is why a
"metadata push" that only touched the version silently leaves the name alone.

Sketch, to run the same pinned way as everything else. Auth and lookup are exactly
what `asc_state.rb` already does; add the writes:

```ruby
# after the Spaceship::ConnectAPI.token = … block from asc_state.rb
app  = Spaceship::ConnectAPI::App.find("com.kfpun.nihongo")
vers = app.get_app_store_versions(filter: { platform: "IOS" }, includes: nil)
target = vers.find { |v| v.version_string == "3.0.0" }   # name it, don't infer it

Spaceship::ConnectAPI::AppStoreVersionLocalization
  .all(app_store_version_id: target.id).each do |loc|
    dir = "fastlane/metadata/#{loc.locale}"
    next unless File.directory?(dir)
    attrs = {}
    { "description.txt" => :description, "keywords.txt" => :keywords,
      "release_notes.txt" => :whats_new, "promotional_text.txt" => :promotional_text,
      "support_url.txt" => :support_url, "marketing_url.txt" => :marketing_url
    }.each { |f, k| attrs[k] = File.read("#{dir}/#{f}").strip if File.exist?("#{dir}/#{f}") }
    loc.update(attributes: attrs)   # PATCH — this is the write
  end
```

`update(attributes:)` takes the **snake_case accessor names** above; it runs them
through `reverse_attr_mapping` to the API's camelCase itself. Writing to a version
Apple has already accepted into review will be refused by the API — that is
correct behaviour, not a bug to work around.

**Only the read half of this is verified on this machine.** `asc_state.rb` has
been run; the PATCH sketch has not. Treat it as a starting point, run it against
one locale first, and read the result back with `asc_state.rb` before doing the
rest.

## Trap 3: `ta` is silently dropped

`Deliver::Loader` partitions locale folders on `valid?`, which tests against the
hardcoded `Deliver::Languages::ALL_LANGUAGES` (39 entries). `ta` is not in it.
`ignore_language_directory_validation: true` — which the Fastfile passes —
**suppresses the error only**; the folder is still discarded, so the text is
never even loaded and the lane reports success having skipped it.

The second, blocking reason is worse: `ta` **doesn't exist on the App Store
version at all**. Step 0 confirms it — 13 ASC localizations (`de-DE`, `en-US`,
`es-ES`, `fr-FR`, `hi`, `id`, `ja`, `ko`, `ru`, `th`, `vi`, `zh-Hans`, `zh-Hant`)
against 14 folders on disk. So there's no destination even going around
fastlane. `fastlane/metadata/ta` is inert reference copy by decision; don't chase
it as a bug. Shipping it means adding Tamil in App Store Connect first.

`fil` used to sit in the same state and was removed outright — store metadata and
rendered screenshots both. Note this is the *store* locale only: `fil` remains one
of the app's 17 **UI** languages in `nihongo/UIStrings.json`, and the promo site
still builds a Filipino page. Don't propagate this removal to either.

Note there is a `ja` localization with no counterpart in the app's own 17 UI
languages — Japanese store text for a Japanese-learning app. Don't "fix" that
asymmetry either.

## Before writing any copy

Re-read **"Product facts copy must not get wrong"** in `CLAUDE.md`. Every item
there was wrong in shipped store copy once. The ones that bite store fields:
**no third-party trademark in the name or subtitle** (Guideline 5.2 — the textbook
name stays out of every user-visible store field), **no free-lesson count**, and
**never "native audio"** (it is `say -v Kyoko` TTS). And metadata is 15 locales:
an English-only edit ships an inconsistent store listing.

## Lanes that are not this skill's job

- `fastlane ios release` — archives and uploads a **build**. It runs `build_app`,
  i.e. it builds the app, which `CLAUDE.md` forbids. Human-only.
- `fastlane ios privacy` — rides Apple's private web API and prompts for an Apple
  ID password and 2FA interactively. Human-only.
- `fastlane ios screenshots` — uploads images, not text; it shares Trap 1 and
  Trap 2 exactly. Generating the images is the `app-store-screenshots` skill.
