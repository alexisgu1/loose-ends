import SwiftUI

/// "Haven't talked in a while" card: same look and grid as HomeCard, with how long it's been.
struct QuietCard: View {
    @EnvironmentObject var store: Store
    let person: QuietPerson

    @State private var draft = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                FlowAvatar(name: person.firstName, size: 24)
                Text(person.firstName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(person.quietFor).font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(height: 24)

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
                Button(editing ? "Done" : "Edit") { editing.toggle(); focused = editing }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("Say hi") {
                    focused = false; editing = false
                    Task { await store.sendQuiet(person, text: draft) }
                }
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
        .onAppear { if draft.isEmpty { draft = person.draft } }
    }
}
