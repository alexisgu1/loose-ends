import SwiftUI

/// This week → (swipe through plans) → N plans made → Next week picker → Preferences saved.
struct PlanDeckView: View {
    @EnvironmentObject var store: Store
    @StateObject private var deck = DeckModel()
    @State private var showSettings = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea().onTapGesture { hideKeyboard() }
            switch deck.phase {
            case .loading: ProgressView().tint(.white)
            case .failed(let msg): failed(msg)
            case .deck, .end:
                // One view for both, so the switch is a true crossfade: the deck dissolves while the
                // end screen comes up in the same moment (never a black frame in between).
                ZStack {
                    deckScreen.compositingGroup()
                        .opacity(deck.phase == .deck ? 1 : 0)
                        .allowsHitTesting(deck.phase == .deck)
                    if deck.phase == .end {
                        EndScreen(deck: deck, calendar: openCalendar).compositingGroup().transition(.opacity)
                    }
                }
            case .pick: PickScreen(deck: deck).transition(.opacity)
            case .saved: SavedScreen(deck: deck, calendar: openCalendar).transition(.opacity)
            }
            ConfettiLayer(bursts: $deck.bursts).ignoresSafeArea().allowsHitTesting(false)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView(deck: deck).environmentObject(store) }
        .task { await deck.load(store: store) }
        .onOpenURL { _ in }   // looseends://deck from the lock screen / island just opens here
    }

    // MARK: deck

    private var deckScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This week").font(.deckTitle)
                .padding(.horizontal, 16).padding(.top, 32)
                .onLongPressGesture { showSettings = true }
            ZStack {
                ForEach(Array(deck.plans.prefix(3).enumerated()), id: \.element.id) { k, p in
                    DeckCard(plan: binding(for: p.id), depth: k) { send in deck.decide(p, send: send, store: store) }
                        .scaleEffect(1 - CGFloat(k) * 0.05, anchor: .bottom)
                        .offset(y: CGFloat(k) * 14)
                        .zIndex(Double(10 - k))
                        .transition(.identity)
                }
            }
            .frame(maxHeight: .infinity)   // keep the space when the last card leaves, so nothing slides together
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 48)   // 28 of peeking cards + 32 to the faces, less the rail's own 12
            FacesRail(deck: deck)
                .padding(.bottom, 36)   // faces sit 48 from the bottom of the screen (rail adds 12)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func binding(for id: String) -> Binding<DeckPlan> {
        Binding(get: { deck.plans.first { $0.id == id } ?? deck.all.first { $0.id == id }! },
                set: { deck.update($0) })
    }

    private func failed(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Text(msg).font(.deckLabel).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.6))
            Button("Try again") { Task { await deck.load(store: store) } }.font(.deckLabel)
            Button("Settings") { showSettings = true }.font(.deckLabel).foregroundStyle(.white.opacity(0.6))
        }
        .padding(32)
    }

    /// Google Calendar app if it's installed, otherwise the web.
    private func openCalendar() {
        openURL(URL(string: "googlecalendar://")!) { ok in
            if !ok { openURL(URL(string: "https://calendar.google.com/calendar/r/week")!) }
        }
    }
}

// MARK: - Faces along the bottom: skipped ones leave, sent ones stay with a check; "2/4" on the right

struct FacesRail: View {
    @ObservedObject var deck: DeckModel
    var body: some View {
        let skipped = deck.frozenRail?.skipped ?? deck.skipped, sentIds = deck.frozenRail?.sent ?? deck.sent
        let currentId = deck.frozenRail.map { $0.current } ?? deck.current?.id
        let shown = deck.all.filter { !skipped.contains($0.id) }
        let n = deck.all.count, i = deck.frozenRail != nil ? n : min(n, n - deck.plans.count + 1)
        HStack(spacing: 8) {
            ForEach(shown) { p in
                let sent = sentIds.contains(p.id), now = currentId == p.id
                Face(name: p.name)
                    .opacity(sent || now ? 1 : 0.35)
                    .overlay(alignment: .bottomTrailing) {
                        if sent {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette).foregroundStyle(.black, .white)
                                .font(.system(size: 18))
                                .background(Circle().fill(.black).padding(-2))
                                .offset(x: 3, y: 3)
                                .transition(.scale(scale: 0.6).combined(with: .opacity).animation(.easeOut(duration: 0.4).delay(0.15)))
                        }
                    }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            Spacer()
            (Text("\(i)").foregroundStyle(.white) + Text("/\(n)").foregroundStyle(.white.opacity(0.3)))
                .font(.deckTitle)
                .contentTransition(.numericText())
                .animation(.smooth, value: i)
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .padding(.horizontal, 16)
    }
}

// MARK: - End: the people you made plans with

struct EndScreen: View {
    @ObservedObject var deck: DeckModel
    let calendar: () -> Void
    var body: some View {
        let ppl = deck.all.filter { deck.sent.contains($0.id) }
        VStack(spacing: 0) {
            Spacer().frame(height: 288 - 62)   // faces start at 288 on the 8pt grid (62 is the status bar)
            if !ppl.isEmpty {
                OverlapFaces(names: ppl.map(\.name), stagger: false).padding(.bottom, 24)
            }
            Text(ppl.isEmpty ? "All caught up" : ppl.count == 1 ? "1 plan made this week" : "\(ppl.count) plans made this week")
                .font(.deckTitle).multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
            BottomButtons(primary: ("Who do you want to see?", { deck.openPicker() }), secondary: ("Check your calendar", calendar), stagger: false)
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }
}

struct OverlapFaces: View {
    let names: [String]
    var stagger = true
    var body: some View {
        HStack(spacing: -16) {
            ForEach(Array(names.enumerated()), id: \.offset) { k, n in
                Face(name: n, size: 64, ring: .black)
                    .zIndex(Double(k))   // last one in front
            }
        }
        .compositingGroup()   // the faces fade in as one picture, so you never see them through each other
        .modifier(MaybeEaseIn(on: stagger))
    }
}

struct BottomButtons: View {
    let primary: (String, () -> Void)
    var secondary: (String, () -> Void)? = nil
    var primaryEnabled = true
    var stagger = true
    var body: some View {
        VStack(spacing: 8) {
            Button(action: primary.1) {
                Text(primary.0).font(.deckLabel).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: Capsule())
            }
            .opacity(primaryEnabled ? 1 : 0.3).disabled(!primaryEnabled)
            if let secondary {
                Button(action: secondary.1) {
                    Text(secondary.0).font(.deckLabel).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 56)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)   // 24 from the bottom of the screen
        .modifier(MaybeEaseIn(on: stagger, order: 2))
    }
}

// MARK: - Next week: pick who you want to see

struct PickScreen: View {
    @ObservedObject var deck: DeckModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Next week").font(.deckTitle).padding(.horizontal, 16).padding(.top, 32)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(deck.candidates.enumerated()), id: \.element.id) { k, q in
                        let on = deck.picked.contains(q.personId)
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if on { deck.picked.removeAll { $0 == q.personId } } else { deck.picked.append(q.personId) }
                            }
                        } label: {
                            HStack(spacing: 16) {
                                Face(name: q.firstName, size: 64)
                                    .opacity(on ? 1 : 0.35)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .symbolRenderingMode(.palette).foregroundStyle(.black, .white)
                                            .font(.system(size: 22))
                                            .background(Circle().fill(.black).padding(-3))
                                            .offset(x: 2, y: 2)
                                            .opacity(on ? 1 : 0).scaleEffect(on ? 1 : 0.6)
                                    }
                                Text(q.firstName).font(.deckMessage).foregroundStyle(.white.opacity(on ? 1 : 0.35))
                                Spacer()
                            }
                            .frame(height: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .easeIn(order: k)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                BottomButtons(primary: ("Save", { deck.savePicks() }), primaryEnabled: !deck.picked.isEmpty)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Preferences saved: nothing to do until next week starts

struct SavedScreen: View {
    @ObservedObject var deck: DeckModel
    let calendar: () -> Void
    var body: some View {
        let names = deck.picked.compactMap { id in deck.candidates.first { $0.personId == id }?.firstName }
        VStack(spacing: 0) {
            Spacer().frame(height: 288 - 62)
            OverlapFaces(names: names).padding(.bottom, 24)
            Text("Preferences saved").font(.deckTitle).easeIn(order: 1)
            Spacer()
            BottomButtons(primary: ("Check your calendar", calendar))
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct MaybeEaseIn: ViewModifier {
    let on: Bool
    var order = 0
    func body(content: Content) -> some View {
        if on { content.easeIn(order: order) } else { content }
    }
}
