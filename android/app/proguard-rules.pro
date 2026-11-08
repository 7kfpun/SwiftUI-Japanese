# App-specific R8 rules. The libraries in use ship their own consumer rules (Play Billing, AdMob and UMP,
# Firebase, Glance, Room, kotlinx.serialization), and `assembleMinnaRelease` (run in CI) builds with R8 and
# resource shrinking on and reports no missing classes, so nothing needs keeping here yet. Add a rule
# only for a failure that build shows, with the reason beside it.
