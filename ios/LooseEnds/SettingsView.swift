import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    var deck: DeckModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var nudgeTime = Date()
    @State private var previewSent = false

    var body: some View {
        NavigationStack {
            Form {
                if let deck {
                    Section {
                        Button {
                            dismiss()
                            Task { await deck.startNextWeek(store: store) }
                        } label: { Label("Skip to next week", systemImage: "forward") }
                            .disabled(deck.savedPickIds.isEmpty)
                        Button {
                            dismiss()
                            PlansActivity.start(names: deck.all.map(\.name))
                        } label: { Label("Show lock-screen card", systemImage: "rectangle.on.rectangle") }
                        Button {
                            dismiss()
                            PlansActivity.demoToday()
                        } label: { Label("Remind me of today's plans", systemImage: "bell") }
                        Button {
                            dismiss()
                            Task { await deck.load(store: store) }
                        } label: { Label("Start this week over", systemImage: "arrow.counterclockwise") }
                    } header: {
                        Text("Demo")
                    } footer: {
                        Text("In real use, next week starts on its own and the lock screen reminds you who you picked.")
                    }
                }
                Section {
                    DatePicker("Remind me at", selection: $nudgeTime, displayedComponents: .hourAndMinute)
                    Button {
                        Nudge.preview(cards: store.digest?.cards ?? [])
                        previewSent = true
                    } label: {
                        Label(previewSent ? "Coming in 5 seconds. Lock your phone." : "Preview tonight's notification",
                              systemImage: "bell.badge")
                    }
                } header: {
                    Text("Nightly nudge")
                } footer: {
                    Text("A notification with tonight's names, like \"3 people worth a text tonight.\"")
                }

                Section {
                    TextField("http://localhost:4321", text: $store.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Pairing code (only over Wi-Fi)", text: $store.pairCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Re-read my messages") {
                        dismiss()
                        Task { await store.load(refresh: true) }
                    }
                } header: {
                    Text("Your Mac")
                } footer: {
                    Text("iPhones can't read iMessages, so the Loose Ends companion on your Mac reads them and sends this app only tonight's list.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .onAppear {
                nudgeTime = Calendar.current.date(bySettingHour: store.nudgeHour, minute: store.nudgeMinute, second: 0, of: .now) ?? .now
            }
            .onChange(of: nudgeTime) { _, t in
                let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                store.nudgeHour = c.hour ?? 21
                store.nudgeMinute = c.minute ?? 0
                Nudge.scheduleTonight(cards: store.digest?.cards ?? [], hour: store.nudgeHour, minute: store.nudgeMinute)
            }
        }
    }
}
