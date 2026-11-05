import SwiftUI
import UIKit

struct CardView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    let card: Card
    @State private var draft = ""
    @State private var showWhy = false
    @FocusState private var editing: Bool

    private var kind: LoopKind { LoopKind(rawValue: card.loop.type) ?? .drift }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            head
            Text(card.loop.why)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            evidence
            if !card.also.isEmpty {
                Text("Also open: " + card.also.map { $0.lowercased() }.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            bubble
            actions
            if showWhy { why }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        .onAppear { if draft.isEmpty { draft = card.loop.draft } }
    }

    private var head: some View {
        HStack(spacing: 12) {
            Avatar(name: card.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.name).font(.headline)
                Text(context).font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            Chip(kind: kind)
        }
    }

    private var context: String {
        let rel = card.relationship == "unknown" ? "" : card.relationship.capitalized + " · "
        return rel + "texted " + Format.relative(card.lastTalked)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("“\(card.loop.quote)”").font(.subheadline)
            Text("\(card.loop.quoteFrom == "me" ? "You" : card.firstName), \(Format.short(card.loop.quoteDate))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: UnevenRoundedRectangle(bottomTrailingRadius: 14, topTrailingRadius: 14))
        .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
    }

    private var bubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Your text", text: $draft, axis: .vertical)
                .focused($editing)
                .font(.body)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.ember, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20))
                .accessibilityLabel("Text to \(card.name)")
            Text(!SendSafety.liveSending ? "Test mode: Send texts you, not \(card.firstName)."
                 : editing ? "Tap Send when it sounds right." : "Written the way you text \(card.firstName). Tap to edit.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: send) {
                Label("Send", systemImage: "paperplane.fill").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .buttonBorderShape(.capsule)

            Menu {
                Button("Tomorrow") { store.act(card, action: "snooze", days: 1) }
                Button("In 3 days") { store.act(card, action: "snooze", days: 3) }
                Button("Next week") { store.act(card, action: "snooze", days: 7) }
            } label: {
                Text("Later").font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.secondary)

            Button { store.act(card, action: "not_close") } label: {
                Text("Not close").font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.secondary)

            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { showWhy.toggle() } } label: {
                Image(systemName: showWhy ? "info.circle.fill" : "info.circle")
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Why this person?")
        }
    }

    private var why: some View {
        let f = card.factors
        return VStack(alignment: .leading, spacing: 8) {
            Text("Ranked by what kind of loose end it is, how close you are, and timing.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Term(label: kind.title, value: f.type)
                Text("×")
                Term(label: card.relationship == "unknown" ? "closeness" : card.relationship, value: 0.5 + 0.5 * f.closeness)
                Text("×")
                Term(label: f.timingNote, value: f.timing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Opens Messages to this person with the draft already typed. You still hit send.
    private func send() {
        editing = false
        let text = draft
        if !SendSafety.liveSending {
            // Test mode: your Mac texts YOU (real iMessage), never the friend.
            Task { await store.testSend(card: card, text: SendSafety.body(for: card, draft: text)) }
            return
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let handle = SendSafety.recipient(for: card)
        let body = SendSafety.body(for: card, draft: text).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "sms:\(handle)&body=\(body)") else { return }
        openURL(url) { opened in
            if !opened {
                // The iOS Simulator has no Messages app.
                UIPasteboard.general.string = text
                store.show(.init(text: "No Messages app here. Draft copied.", undo: nil))
            }
            store.act(card, action: "send", draft: text)
        }
    }
}

struct Term: View {
    let label: String
    let value: Double
    var body: some View {
        HStack(spacing: 3) {
            Text(label).lineLimit(1)
            Text(value, format: .number.precision(.fractionLength(2))).bold().foregroundStyle(.primary)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct Avatar: View {
    let name: String
    var body: some View {
        Text(initials)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(Color(hue: hue, saturation: 0.45, brightness: 0.72), in: Circle())
    }
    private var initials: String {
        let parts = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let s = parts.prefix(2).compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "#" : s.uppercased()
    }
    private var hue: Double {
        var h = 0
        for u in name.unicodeScalars { h = (h * 31 + Int(u.value)) % 360 }
        return Double(h) / 360
    }
}

struct Chip: View {
    let kind: LoopKind
    var body: some View {
        Text(kind.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
    private var color: Color {
        switch kind {
        case .event: .blue
        case .reply_owed: .red
        case .promise: .orange
        case .plan: .green
        case .drift: .purple
        }
    }
}

enum Format {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func relative(_ s: String) -> String {
        guard let d = iso.date(from: s) else { return "" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<14: return "last week"
        case 14..<60: return "\(days / 7) weeks ago"
        default: return "\(days / 30) months ago"
        }
    }

    static func short(_ ymd: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: ymd) else { return ymd }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
