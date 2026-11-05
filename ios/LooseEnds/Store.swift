import Foundation
import SwiftUI

/// Talks to the Mac companion (which reads your real iMessages) and holds tonight's list.
@MainActor
final class Store: ObservableObject {
    enum Phase {
        case loading
        case loaded
        case failed(title: String, message: String)
    }

    struct Toast: Identifiable {
        let id = UUID()
        let text: String
        let undo: (id: String, personId: String)?
    }

    @Published var phase: Phase = .loading
    @Published var digest: Digest?
    @Published var toast: Toast?
    @Published var focusId: String?

    @AppStorage("serverURL") var serverURL = "http://localhost:4321"
    @AppStorage("pairCode") var pairCode = ""
    @AppStorage("nudgeHour") var nudgeHour = 21
    @AppStorage("nudgeMinute") var nudgeMinute = 0

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces) + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 180) // first AI read of real threads can take a while
        req.httpMethod = method
        if !pairCode.isEmpty { req.setValue(pairCode, forHTTPHeaderField: "x-pair-code") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    func load(refresh: Bool = false) async {
        if digest == nil { phase = .loading }
        guard let req = request("/api/digest" + (refresh ? "?refresh=1" : "")) else {
            phase = .failed(title: "Check the Mac address", message: "\"\(serverURL)\" isn't a valid address. Fix it in Settings.")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                let d = try decoder.decode(Digest.self, from: data)
                digest = d
                phase = .loaded
                Nudge.scheduleTonight(cards: d.cards, hour: nudgeHour, minute: nudgeMinute)
            } else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                phase = .failed(
                    title: status == 403 ? "Your Mac can't read Messages yet" : status == 401 ? "Pairing code needed" : "Something went wrong",
                    message: msg ?? "The Mac companion returned an error (\(status))."
                )
            }
        } catch {
            if digest == nil {
                phase = .failed(
                    title: "Can't reach your Mac",
                    message: "Start the companion on your Mac with `npm start` in the loose-ends folder. On a real iPhone, use your Mac's Wi-Fi address in Settings."
                )
            }
        }
    }

    func act(_ card: Card, action: String, days: Int? = nil, draft: String? = nil) {
        var body: [String: Any] = ["action": action, "id": card.id, "personId": card.personId]
        if let days { body["days"] = days }
        if let draft { body["draft"] = draft }
        // Test sends aren't saved, so a pull-to-refresh brings the person back for more testing.
        let isTestSend = action == "send" && !SendSafety.liveSending
        if !isTestSend, let req = request("/api/action", method: "POST", body: body) {
            Task { _ = try? await URLSession.shared.data(for: req) }
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            digest?.cards.removeAll { $0.id == card.id }
            if action == "send" { digest?.stats.handled += 1 }
            if action == "snooze" { digest?.stats.snoozed += 1 }
        }
        let text: String = switch action {
        case "send": "Nice. \(card.firstName) will be happy to hear from you."
        case "snooze": days == 1 ? "\(card.firstName) will come back tomorrow." : "\(card.firstName) will come back in \(days ?? 1) days."
        default: "Won't suggest \(card.firstName) again."
        }
        show(Toast(text: text, undo: (card.id, card.personId)))
    }

    /// Test mode: the Mac companion sends the draft to your own number via iMessage.
    func testSend(card: Card, text: String) async {
        if !TestMode.sendTexts {
            act(card, action: "send", draft: text)
            show(Toast(text: "Dry run: nothing was sent.", undo: nil))
            return
        }
        guard let req = request("/api/test-send", method: "POST", body: ["text": text]) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                act(card, action: "send", draft: text)
                show(Toast(text: "Texted you instead of \(card.firstName). Check your phone.", undo: nil))
            } else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                show(Toast(text: msg ?? "Your Mac couldn't send it.", undo: nil))
            }
        } catch {
            show(Toast(text: "Can't reach your Mac.", undo: nil))
        }
    }

    // MARK: Google Calendar plans

    /// The first evening this week you're both free (or just you, if their calendar isn't visible).
    func fetchPlan(name: String, day: Int = 0) async -> PlanInfo? {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let req = request("/api/plan?name=\(q)&day=\(day)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(PlanInfo.self, from: data)
    }

    /// Put the plan on your calendar (no invite goes out while invites are off on the Mac).
    func createPlan(_ p: PlanInfo) async {
        guard let slot = p.slot, let req = request("/api/plan", method: "POST", body: [
            "title": p.title ?? "Dinner", "start": slot.start, "end": slot.end, "email": p.email ?? "",
        ]) else { return }
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Plan deck, swipe right: put "<place> with <name>" on YOUR calendar. No invite goes out
    /// (invites are off on the Mac: SEND_INVITES = false).
    @discardableResult
    func addPlanToCalendar(_ p: DeckPlan) async -> (link: URL, id: String)? {
        guard let req = request("/api/plan", method: "POST", body: [
            "title": "\(p.place) with \(p.name)", "start": Fmt.iso.string(from: p.start), "end": Fmt.iso.string(from: p.end), "email": p.email ?? "",
            "location": Near.location(for: p.place),
        ]) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let link = (j["link"] as? String).flatMap(URL.init(string:)), let id = j["id"] as? String else { return nil }
        return (link, id)
    }

    /// Take a plan you made back off your calendar (the Mac only deletes events this app created).
    func deletePlanEvent(id: String) async {
        guard let req = request("/api/plan/delete", method: "POST", body: ["id": id]) else { return }
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Plan deck, swipe right: the text. Dry run unless TestMode.sendTexts (then it texts YOUR number only).
    func sendPlanText(_ p: DeckPlan) {
        if TestMode.sendTexts, let req = request("/api/test-send", method: "POST", body: ["text": "[TEST → \(p.name)] \(p.text)"]) {
            Task { _ = try? await URLSession.shared.data(for: req) }
        }
    }

    // MARK: flow actions (no toasts; the card flying away is the feedback)

    /// Tonight: send. Dry run unless TestMode.sendTexts (then it texts YOUR number only).
    func flowSend(_ card: Card, text: String) {
        if TestMode.sendTexts, let req = request("/api/test-send", method: "POST", body: ["text": SendSafety.body(for: card, draft: text)]) {
            Task { _ = try? await URLSession.shared.data(for: req) }
        }
        flowRemove(card)
    }

    /// Tonight: skip. Comes back tomorrow (saved on the Mac only when real test sends are on).
    func flowSkip(_ card: Card) {
        if TestMode.sendTexts, let req = request("/api/action", method: "POST", body: ["action": "snooze", "id": card.id, "personId": card.personId, "days": 1]) {
            Task { _ = try? await URLSession.shared.data(for: req) }
        }
        flowRemove(card)
    }

    private func flowRemove(_ card: Card) {
        // Animate closing the gap between cards, but not the switch to the next screen (that fades in on its own).
        if (digest?.cards.count ?? 0) > 1 {
            withAnimation(.smooth(duration: 0.3)) { digest?.cards.removeAll { $0.id == card.id } }
        } else {
            digest?.cards.removeAll { $0.id == card.id }
        }
    }

    /// Reach out: send. Dry run unless TestMode.sendTexts (then it texts YOUR number only).
    func sendQuiet(_ q: QuietPerson, text: String) {
        if TestMode.sendTexts, let req = request("/api/test-send", method: "POST", body: ["text": "[TEST → \(q.firstName)] \(text)"]) {
            Task { _ = try? await URLSession.shared.data(for: req) }
        }
    }

    func undo(_ t: Toast) {
        guard let u = t.undo, let req = request("/api/action", method: "POST", body: ["action": "undo", "id": u.id, "personId": u.personId]) else { return }
        toast = nil
        Task {
            _ = try? await URLSession.shared.data(for: req)
            await load()
        }
    }

    func show(_ t: Toast) {
        withAnimation(.spring) { toast = t }
        let id = t.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toast?.id == id { withAnimation(.easeOut) { toast = nil } }
        }
    }
}
