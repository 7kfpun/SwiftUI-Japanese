# Updates the premium products in App Store Connect via the official API:
#   - fixes the 3M subscription's duration (was 2 months) and puts all subs on level 1
#   - upserts localized display names/descriptions for the 3 subscriptions,
#     the subscription group, and the lifetime in-app purchase (14 locales)
# Prices and review screenshots are intentionally left to the ASC UI.
#
# Run: BUNDLE_PATH=vendor/bundle bundle exec ruby scripts/asc_update_subscriptions.rb
# Credentials come from fastlane/.env (git-ignored).

require "jwt"
require "json"
require "net/http"
require "openssl"

# --- auth -------------------------------------------------------------------
env = File.readlines("fastlane/.env").map { |l|
  l = l.strip
  next if l.empty? || l.start_with?("#")
  l.split("=", 2)
}.compact.to_h
KEY_ID    = env.fetch("ASC_KEY_ID")
ISSUER_ID = env.fetch("ASC_ISSUER_ID")
KEY_PATH  = File.expand_path(env.fetch("ASC_KEY_PATH"))

def token
  key = OpenSSL::PKey.read(File.read(KEY_PATH))
  JWT.encode(
    { iss: ISSUER_ID, iat: Time.now.to_i, exp: Time.now.to_i + 15 * 60, aud: "appstoreconnect-v1" },
    key, "ES256", { kid: KEY_ID }
  )
end

BASE = URI("https://api.appstoreconnect.apple.com")
def request(method, path, body = nil)
  http = Net::HTTP.new(BASE.host, 443)
  http.use_ssl = true
  req = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PATCH" => Net::HTTP::Patch }
          .fetch(method).new(path)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"
  req.body = JSON.generate(body) if body
  res = http.request(req)
  parsed = res.body && !res.body.empty? ? JSON.parse(res.body) : {}
  unless res.code.to_i.between?(200, 299)
    warn "  !! #{method} #{path} -> #{res.code}: #{parsed.dig('errors', 0, 'detail') || res.body&.slice(0, 200)}"
    return nil
  end
  parsed
end

APP_ID   = "1447639161"
GROUP_ID = "20499759"

# --- localized copy (name <= 30 chars, description <= 45 chars) --------------
# locale => [1m name, 3M name, 6M name, lifetime name, description, group display name]
L10N = {
  "en-US"   => ["1 Month", "3 Months", "6 Months", "Lifetime", "All 50 lessons, ad-free.", "Premium"],
  "zh-Hans" => ["1 个月", "3 个月", "6 个月", "永久", "解锁全部 50 课，无广告。", "高级版"],
  "zh-Hant" => ["1 個月", "3 個月", "6 個月", "終身", "解鎖全部 50 課,無廣告。", "進階版"],
  "ja"      => ["1か月", "3か月", "6か月", "買い切り", "全50レッスン解放、広告なし。", "プレミアム"],
  "ko"      => ["1개월", "3개월", "6개월", "평생", "50개 레슨 모두, 광고 없음.", "프리미엄"],
  "vi"      => ["1 tháng", "3 tháng", "6 tháng", "Trọn đời", "Mở khoá 50 bài, không quảng cáo.", "Cao cấp"],
  "th"      => ["1 เดือน", "3 เดือน", "6 เดือน", "ตลอดชีพ", "ปลดล็อกครบ 50 บท ไม่มีโฆษณา", "พรีเมียม"],
  "de-DE"   => ["1 Monat", "3 Monate", "6 Monate", "Lebenslang", "Alle 50 Lektionen, werbefrei.", "Premium"],
  "es-ES"   => ["1 mes", "3 meses", "6 meses", "De por vida", "Las 50 lecciones, sin anuncios.", "Premium"],
  "es-MX"   => ["1 mes", "3 meses", "6 meses", "De por vida", "Las 50 lecciones, sin anuncios.", "Premium"],
  "fr-FR"   => ["1 mois", "3 mois", "6 mois", "À vie", "Les 50 leçons, sans pub.", "Premium"],
  "hi"      => ["1 महीना", "3 महीने", "6 महीने", "आजीवन", "सभी 50 पाठ, बिना विज्ञापन।", "प्रीमियम"],
  "id"      => ["1 bulan", "3 bulan", "6 bulan", "Seumur hidup", "Semua 50 pelajaran, tanpa iklan.", "Premium"],
  "ru"      => ["1 месяц", "3 месяца", "6 месяцев", "Навсегда", "Все 50 уроков, без рекламы.", "Премиум"],
}
NAME_INDEX = { "com.kfpun.nihongo.premium.1m" => 0, "com.kfpun.nihongo.premium.3M" => 1,
               "com.kfpun.nihongo.premium.6M" => 2 }

# --- 1. subscriptions: duration + level + localizations ----------------------
subs = request("GET", "/v1/subscriptionGroups/#{GROUP_ID}/subscriptions?limit=50")
abort("cannot list subscriptions") unless subs
subs["data"].each do |sub|
  id  = sub["id"]
  pid = sub.dig("attributes", "productId")
  idx = NAME_INDEX[pid]
  next unless idx
  puts "== #{pid} (#{id})"

  attrs = { "groupLevel" => 1 }
  attrs["subscriptionPeriod"] = "THREE_MONTHS" if pid.end_with?(".3M")
  request("PATCH", "/v1/subscriptions/#{id}",
          { data: { type: "subscriptions", id: id, attributes: attrs } }) &&
    puts("   level=1#{attrs['subscriptionPeriod'] ? ', duration=3 months' : ''} ✓")

  existing = request("GET", "/v1/subscriptions/#{id}/subscriptionLocalizations?limit=50")
  existing_by_locale = (existing&.dig("data") || []).to_h { |l| [l.dig("attributes", "locale"), l["id"]] }
  L10N.each do |locale, row|
    name, desc = row[idx], row[4]
    if (loc_id = existing_by_locale[locale])
      request("PATCH", "/v1/subscriptionLocalizations/#{loc_id}",
              { data: { type: "subscriptionLocalizations", id: loc_id,
                        attributes: { name: name, description: desc } } })
    else
      request("POST", "/v1/subscriptionLocalizations",
              { data: { type: "subscriptionLocalizations",
                        attributes: { name: name, locale: locale, description: desc },
                        relationships: { subscription: { data: { type: "subscriptions", id: id } } } } })
    end
  end
  puts "   localizations upserted (#{L10N.size})"
end

# --- 2. subscription group display names -------------------------------------
existing = request("GET", "/v1/subscriptionGroups/#{GROUP_ID}/subscriptionGroupLocalizations?limit=50")
group_by_locale = (existing&.dig("data") || []).to_h { |l| [l.dig("attributes", "locale"), l["id"]] }
L10N.each do |locale, row|
  display = row[5]
  if (loc_id = group_by_locale[locale])
    request("PATCH", "/v1/subscriptionGroupLocalizations/#{loc_id}",
            { data: { type: "subscriptionGroupLocalizations", id: loc_id,
                      attributes: { name: display } } })
  else
    request("POST", "/v1/subscriptionGroupLocalizations",
            { data: { type: "subscriptionGroupLocalizations",
                      attributes: { name: display, locale: locale },
                      relationships: { subscriptionGroup: { data: { type: "subscriptionGroups", id: GROUP_ID } } } } })
  end
end
puts "== group display names upserted (#{L10N.size})"

# --- 3. lifetime IAP localizations -------------------------------------------
iaps = request("GET", "/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=200")
life = (iaps&.dig("data") || []).find { |i| i.dig("attributes", "productId") == "com.kfpun.nihongo.premium.lifetime" }
if life
  lid = life["id"]
  puts "== lifetime IAP (#{lid})"
  existing = request("GET", "/v1/inAppPurchasesV2/#{lid}/inAppPurchaseLocalizations?limit=50")
  by_locale = (existing&.dig("data") || []).to_h { |l| [l.dig("attributes", "locale"), l["id"]] }
  L10N.each do |locale, row|
    name, desc = row[3], row[4]
    if (loc_id = by_locale[locale])
      request("PATCH", "/v1/inAppPurchaseLocalizations/#{loc_id}",
              { data: { type: "inAppPurchaseLocalizations", id: loc_id,
                        attributes: { name: name, description: desc } } })
    else
      request("POST", "/v1/inAppPurchaseLocalizations",
              { data: { type: "inAppPurchaseLocalizations",
                        attributes: { name: name, locale: locale, description: desc },
                        relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: lid } } } } })
    end
  end
  puts "   localizations upserted (#{L10N.size})"
else
  puts "== lifetime IAP not found (skipped)"
end

puts "\nDone. Remaining for the ASC UI: prices + review screenshots, then Add for Review."
