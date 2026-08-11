# READ-ONLY diagnostic for the push-app-store-metadata skill. Makes GETs only.
#
#   cd <repo root>
#   PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/bundle exec \
#     ruby .claude/skills/push-app-store-metadata/asc_state.rb
#
# Prints: every App Store version and its appVersionState, whether fastlane's
# `get_edit_app_store_version` can see one (the thing `deliver` needs), and which
# localizations actually exist to write to. Run this FIRST, every time — it is the
# difference between "deliver will work" and ten minutes of exponential backoff.
require "spaceship"

# Credentials from the git-ignored fastlane/.env (see fastlane/.env.example).
env = File.readlines("fastlane/.env").map { |l|
  l = l.strip
  next if l.empty? || l.start_with?("#")
  l.split("=", 2)
}.compact.to_h

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: env.fetch("ASC_KEY_ID"),
  issuer_id: env.fetch("ASC_ISSUER_ID"),
  filepath: File.expand_path(env.fetch("ASC_KEY_PATH")),
)

app = Spaceship::ConnectAPI::App.find("com.kfpun.nihongo")
puts "app #{app.id} — #{app.name}"

puts "\nversions:"
app.get_app_store_versions(filter: { platform: "IOS" }, includes: nil).each do |v|
  puts "  #{v.version_string.ljust(8)} #{v.app_store_state}"
end

# The exact call `deliver` makes. Its filter list is
# PREPARE_FOR_SUBMISSION / DEVELOPER_REJECTED / REJECTED / METADATA_REJECTED /
# WAITING_FOR_REVIEW / INVALID_BINARY — and nothing else. nil here means deliver
# will retry with backoff and then fail with "Cannot find edit app store version".
edit = app.get_edit_app_store_version(platform: Spaceship::ConnectAPI::Platform::IOS)
puts "\nget_edit_app_store_version -> " +
     (edit ? "#{edit.version_string} (#{edit.app_store_state}) — deliver can edit this" \
           : "nil — DELIVER WILL FAIL, use Spaceship directly on a specific version id")

target = edit || app.get_app_store_versions(filter: { platform: "IOS" }, includes: nil).first
if target
  locs = Spaceship::ConnectAPI::AppStoreVersionLocalization.all(app_store_version_id: target.id)
  puts "\nversion #{target.version_string} localizations (#{locs.size}): " +
       locs.map(&:locale).sort.join(", ")
end

info = app.fetch_edit_app_info
if info
  ils = info.get_app_info_localizations
  puts "app_info #{info.id} localizations (#{ils.size}): " + ils.map(&:locale).sort.join(", ")
end

# Locale folders on disk vs. locales that exist in App Store Connect. Anything in
# the first list and not the second gets no text — `ta` is deliberately in that
# position (see fastlane/Fastfile's header note).
on_disk = Dir.children("fastlane/metadata").select { |d| File.directory?("fastlane/metadata/#{d}") }
in_asc = info ? info.get_app_info_localizations.map(&:locale) : []
puts "\nmetadata/ folders with no ASC localization: #{(on_disk - in_asc).sort.join(', ')}"
