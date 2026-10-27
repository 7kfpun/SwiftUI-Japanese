import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Read along on the Lock Screen and in the Dynamic Island.
///
/// Lives in the existing widget extension: a Live Activity is a WidgetKit view, and
/// this target is already embedded, signed and in the App Group. A second extension
/// would be a new App ID for the same UI. The group is not read here — the content
/// arrives on `ActivityAttributes`.
///
/// Labels are strings the app already localized. This extension does not have
/// `UIStrings.json`, and a hardcoded English caption would be the one surface that
/// ignored the in-app language.
struct ReadAlongLiveActivity: Widget {
    /// Same teal as the app, brighter on a dark island so it still reads.
    private var accent: Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark
                ? Course.current.accentDark
                : Course.current.accentLight
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadAlongAttributes.self) { context in
            lockScreen(context)
                .widgetURL(ReadAlongLink.url(lesson: context.attributes.lesson))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(context.state))
                        .font(.title3)
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    playPause(context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.word)
                        .font(.custom("HiraMinProN-W3", size: 20, relativeTo: .title3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Text(context.state.lessonTitle)
                        Spacer(minLength: 8)
                        Text(context.state.progressLabel)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            } compactLeading: {
                Image(systemName: symbol(context.state))
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(position(context.state))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            } minimal: {
                Image(systemName: symbol(context.state))
                    .foregroundStyle(accent)
            }
            .widgetURL(ReadAlongLink.url(lesson: context.attributes.lesson))
        }
    }

    private func lockScreen(_ context: ActivityViewContext<ReadAlongAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(context.state))
                .font(.title2)
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.lessonTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(context.state.word)
                    .font(.custom("HiraMinProN-W3", size: 22, relativeTo: .title2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(context.state.progressLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(context.state.statusLabel) · \(context.state.modeLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            playPause(context.state)
        }
        .opacity(context.isStale ? 0.5 : 1)
    }

    private func playPause(_ state: ReadAlongAttributes.ContentState) -> some View {
        Button(intent: ToggleReadAlongIntent()) {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundStyle(accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.actionLabel)
    }

    private func symbol(_ state: ReadAlongAttributes.ContentState) -> String {
        state.isPlaying ? "waveform" : "pause.fill"
    }

    /// Digits only — the localized "Word n of m" is the expanded and Lock Screen line.
    private func position(_ state: ReadAlongAttributes.ContentState) -> String {
        "\(state.index + 1)/\(max(state.count, 1))"
    }
}
