import SwiftUI

struct TonightView: View {
    @EnvironmentObject var store: Store
    @State private var showSettings = false
    @AppStorage("askedForNotifications") private var askedForNotifications = false

    // Reach out state (after tonight's list is done)
    private enum ReachStep { case pick, cards }
    @State private var reachStep: ReachStep = .pick
    @State private var round = 1
    @State private var picked: Set<String> = []
    @State private var handled: Set<String> = []       // reach-out people sent or skipped
    @State private var sentNames: [String] = []         // everyone texted tonight, for the faces
    @State private var preselected = false
    @State private var plans: [String: PlanInfo] = [:]  // free evenings from Google Calendar, by person

    private enum Phase: Equatable { case tonight, pick, reach, done }
    private var flowPhase: Phase {
        guard let d = store.digest else { return .tonight }
        if !d.cards.isEmpty { return .tonight }
        if reachStep == .pick && !pool.isEmpty { return .pick }
        if reachStep == .cards && pool.contains(where: { picked.contains($0.id) && !handled.contains($0.id) }) { return .reach }
        return .done
    }
    /// Round 1 = top 5. "Reach out to someone" = whoever's left plus the next few.
    private var pool: [QuietPerson] {
        let all = store.digest?.quiet ?? []
        return round == 1 ? Array(all.prefix(5)) : all.filter { !handled.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // v3 phone grid: 16 margins, 16 between cards.
                    VStack(alignment: .leading, spacing: 16) {
                        if let t = pageTitle {
                            Text(t)
                                .font(.system(size: 34, weight: .bold))
                                .frame(height: 40)
                                .padding(.top, 48)
                                .padding(.bottom, 16)   // 32 to the first card (16 + stack spacing)
                                .contentTransition(.opacity)
                                // Settings lives behind a long-press on the title.
                                .onLongPressGesture { showSettings = true }
                                .accessibilityHint("Long-press for settings")
                        }
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(flowPhase)
                    .transition(.opacity)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(flowPhase == .done)
                .onChange(of: store.focusId) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                    store.focusId = nil
                }
            }
            .overlay(alignment: .bottom) { EdgeBlur() }
            .overlay(alignment: .top) { EdgeBlur(top: true, height: 48) }
            .safeAreaInset(edge: .bottom) { bottomAction }
            .background(Color.black.ignoresSafeArea())
            .refreshable { await store.load(refresh: false) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .overlay(alignment: .bottom) { toast }
        }
        .preferredColorScheme(.dark)
        .task {
            if !askedForNotifications {
                askedForNotifications = true
                _ = await Nudge.requestPermission()
            }
            await store.load()
        }
        .onOpenURL { url in
            // Deep links: looseends://edit/<id> opens straight to that person.
            if url.host == "edit", let id = url.pathComponents.last?.removingPercentEncoding {
                store.focusId = id
                return
            }
            guard url.host == "send", let id = url.pathComponents.last?.removingPercentEncoding,
                  let card = store.digest?.cards.first(where: { $0.id == id }) else { return }
            if SendSafety.liveSending { return } // live flow added once real sending is unlocked
            Task { await store.testSend(card: card, text: SendSafety.body(for: card, draft: card.loop.draft)) }
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            headline
                .font(.system(size: 44, weight: .regular, design: .serif))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(subline)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var when: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h >= 17 || h < 4 ? "Tonight" : h < 12 ? "This morning" : "Today"
    }

    private var headline: Text {
        guard case .loaded = store.phase, let d = store.digest else { return Text(when) }
        let n = d.cards.count
        if n == 0 { return Text("\(when), ") + Text("all clear").italic().foregroundColor(.ember) }
        return Text("\(when), ") + Text("\(n)").italic().foregroundColor(.ember) + Text(n == 1 ? " person" : " people")
    }

    private var subline: String {
        switch store.phase {
        case .loading: "Reading your week…"
        case .failed: ""
        case .loaded: (store.digest?.cards.isEmpty ?? true) ? "Nothing is slipping. Go to bed." : "Worth a quick text before you sleep."
        }
    }

    // MARK: content

    private var pageTitle: String? {
        guard case .loaded = store.phase else { return "Tonight" }
        switch flowPhase {
        case .tonight: return "Tonight"
        case .pick, .reach: return "Reach out"
        case .done: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            LoadingView()
        case let .failed(title, message):
            Notice(title: title, message: message, action: ("Try again", { Task { await store.load() } }))
        case .loaded:
            if let d = store.digest {
                switch flowPhase {
                case .tonight:
                    ForEach(Array(d.cards.enumerated()), id: \.element.id) { k, card in
                        FlowCard(item: FlowItem(id: card.id, name: card.firstName.capitalized, draft: card.loop.draft),
                                 onSend: { text in sentNames.append(card.firstName.capitalized); store.flowSend(card, text: text) },
                                 onSkip: { store.flowSkip(card) })
                            .id(card.id)
                            .easeIn(order: k)
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                case .pick:
                    ReachPicker(people: pool, picked: $picked)
                        .easeIn(order: 0)
                        .onAppear {
                            if !preselected { preselected = true; picked = Set(pool.prefix(3).map(\.id)) }
                        }
                case .reach:
                    ForEach(Array(pool.filter { picked.contains($0.id) && !handled.contains($0.id) }.enumerated()), id: \.element.id) { k, q in
                        let plan = plans[q.id]
                        FlowCard(item: FlowItem(id: q.id, name: q.firstName, draft: plan?.draft ?? q.draft),
                                 plan: plan?.label.map { "\($0) · " + ((plan?.bothFree ?? false) ? "you're both free" : "you're free") },
                                 onSend: { text in
                                     // Calendar first, then the text that mentions it.
                                     if let plan, plan.slot != nil { Task { await store.createPlan(plan) } }
                                     store.sendQuiet(q, text: text)
                                     sentNames.append(q.firstName)
                                     markHandled(q.id)
                                 },
                                 onSkip: { markHandled(q.id) })
                            .id(q.id)
                            .easeIn(order: k)
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                case .done:
                    VStack(spacing: 32) {
                        CaughtUpFaces(names: sentNames.isEmpty ? d.cards.map(\.firstName) : sentNames)
                        Text("You're all caught up")
                            .font(.system(size: 28, weight: .bold))
                            .onLongPressGesture { showSettings = true }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 240)
                    .easeIn(order: 0)
                }
            }
        }
    }

    /// Close the gap smoothly, unless it was the last card (then the next screen just fades in).
    private func markHandled(_ id: String) {
        let left = pool.filter { picked.contains($0.id) && !handled.contains($0.id) }.count
        if left > 1 { withAnimation(.smooth(duration: 0.3)) { _ = handled.insert(id) } } else { handled.insert(id) }
    }

    @ViewBuilder
    private var bottomAction: some View {
        if case .loaded = store.phase {
            switch flowPhase {
            case .pick:
                BottomCTA(title: "Next", enabled: !picked.isEmpty) {
                    // Look up a free evening for each picked person, then show their cards.
                    let chosen = pool.filter { picked.contains($0.id) }
                    Task {
                        for q in chosen where plans[q.id] == nil {
                            if let p = await store.fetchPlan(name: q.name), p.connected { plans[q.id] = p }
                        }
                        reachStep = .cards
                    }
                }
            case .done where !(store.digest?.quiet ?? []).filter({ !handled.contains($0.id) }).isEmpty:
                BottomCTA(title: "Reach out to someone") {
                    round = 2; picked = []; preselected = true; reachStep = .pick
                }
            default:
                EmptyView()
            }
        }
    }

    private func footer(_ d: Digest) -> some View {
        VStack(spacing: 6) {
            Text("Read \(d.stats.messages) texts from \(d.stats.people) people"
                 + (d.stats.overflow > 0 ? " · \(d.stats.overflow) more saved for another night" : ""))
            Label(d.engine == "claude" ? "Read by \(d.model ?? "Claude")" : "Offline mode: add an API key on your Mac for AI",
                  systemImage: d.engine == "claude" ? "sparkles" : "exclamationmark.circle")
            Text("Nothing is ever sent without you.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: toast

    @ViewBuilder
    private var toast: some View {
        if let t = store.toast {
            HStack(spacing: 14) {
                Text(t.text).font(.subheadline).lineLimit(2)
                if t.undo != nil {
                    Button("Undo") { store.undo(t) }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 10)
            .background(Color.primary, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            .padding(.horizontal, 16).padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - small pieces

struct Mark: View {
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.83)
            .stroke(Color.ember, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .rotationEffect(.degrees(-60))
            .frame(width: 18, height: 18)
    }
}

struct Background: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(colors: [Color.ember.opacity(0.12), .clear], center: .top, startRadius: 0, endRadius: 420)
                .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}

struct LoadingView: View {
    @State private var step = 0
    private let steps = [
        "Reading the last 60 days of 1:1 texts",
        "Finding plans, promises, and questions left hanging",
        "Writing drafts in your voice",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle().fill(i <= step ? Color.white : Color.white.opacity(0.25)).frame(width: 8, height: 8)
                    Text(steps[i]).foregroundStyle(i <= step ? .primary : .secondary)
                }
                .font(.subheadline)
            }
            ForEach(0..<2) { i in
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.11))
                    .frame(height: 220).opacity(i == 0 ? 1 : 0.6)
                    .redacted(reason: .placeholder)
            }
            .padding(.top, 6)
        }
        .task {
            for i in 1..<steps.count {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { step = i }
            }
        }
    }
}

struct Notice: View {
    let title: String
    let message: String
    let action: (String, () -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(.init(message)).font(.subheadline).foregroundStyle(.secondary)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.bordered).padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct CaughtUp: View {
    let stats: Stats
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.14), in: Circle())
                .padding(.bottom, 8)
            Text("You're all caught up").font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 14)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
    private var detail: String {
        var bits: [String] = []
        if stats.handled > 0 { bits.append("You reached \(stats.handled) \(stats.handled == 1 ? "person" : "people")") }
        if stats.snoozed > 0 { bits.append("\(stats.snoozed) saved for later") }
        return bits.isEmpty ? "No loose ends tonight." : bits.joined(separator: " · ") + "."
    }
}
