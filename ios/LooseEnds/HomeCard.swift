import SwiftUI

/// A1 on the v3 phone grid (8pt base, 16 gutter), same look as the lock-screen card:
/// 16 padding · 24 name row · 8 · message (24pt lines) · 16 · 40 buttons · 16.
/// Tap the name to see why they're on tonight's list.
struct HomeCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    let card: Card

    @State private var draft = ""
    @State private var showWhy = false
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { showWhy.toggle() } } label: {
                HStack(spacing: 8) {
                    FlowAvatar(name: card.firstName.capitalized, size: 24)
                    Text(card.firstName.capitalized).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showWhy {
                Text(card.loop.why)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            Group {
                if editing {
                    TextField("Your text", text: $draft, axis: .vertical)
                        .focused($focused)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Text(draft).lineLimit(2)
                }
            }
            .font(.system(size: 16))
            .lineSpacing(3)
            .opacity(0.92)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)

            HStack(spacing: 16) {
                Button(editing ? "Done" : "Edit") {
                    editing.toggle()
                    focused = editing
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Send", action: send)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .padding(.top, 16)
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(Color(red: 0.11, green: 0.11, blue: 0.118), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear { if draft.isEmpty { draft = card.loop.draft } }
    }

    private func send() {
        focused = false
        editing = false
        let text = draft
        if !SendSafety.liveSending {
            // Test mode (and dry run while TestMode.sendTexts is off): never texts the friend.
            Task { await store.testSend(card: card, text: SendSafety.body(for: card, draft: text)) }
            return
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let handle = SendSafety.recipient(for: card)
        let body = SendSafety.body(for: card, draft: text).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "sms:\(handle)&body=\(body)") else { return }
        openURL(url)
        store.act(card, action: "send", draft: text)
    }
}
