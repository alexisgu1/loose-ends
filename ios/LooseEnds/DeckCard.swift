import SwiftUI
import UIKit

// Type: three styles only. Title 34/bold · Message 22/regular · Label 15/medium.
extension Font {
    static let deckTitle = Font.system(size: 34, weight: .bold)
    static let deckMessage = Font.system(size: 22, weight: .regular)
    static let deckLabel = Font.system(size: 15, weight: .medium)
}

/// Gray Apple-style initial avatar.
struct Face: View {
    let name: String
    var size: CGFloat = 40
    var ring: Color? = nil
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.647, green: 0.663, blue: 0.706), Color(red: 0.490, green: 0.506, blue: 0.549)],
                                       startPoint: .top, endPoint: .bottom), in: Circle())
            .background { if let ring { Circle().fill(ring).padding(-2) } }
    }
}

// MARK: - Card

struct DeckCard: View {
    @Binding var plan: DeckPlan
    let depth: Int                 // 0 = front
    let onDecide: (Bool) -> Void   // true = send

    @State private var dx: CGFloat = 0
    @State private var locked = false
    @FocusState private var editing: Bool
    @State private var editingText = false
    @State private var placeSpan: Range<Int>?   // where the place sits in the message, while you edit

    private var isTop: Bool { depth == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Face(name: plan.name)
                Text(plan.name).font(.deckLabel)
            }
            // At rest it's plain Text, so a change from 1 line to 2 (or back) animates its height and the
            // calendar glides; tap it to edit in place.
            ZStack(alignment: .topLeading) {
                if editingText {
                    TextField("", text: $plan.text, axis: .vertical)
                        .tint(.black)   // the app tint is white; on the white card the cursor needs to be black to show
                        .font(.deckMessage)
                        .lineSpacing(6)
                        .focused($editing)
                        .onSubmit { editingText = false }
                        .onChange(of: editing) { _, f in if !f { editingText = false } }
                } else {
                    Text(plan.text)
                        .font(.deckMessage)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                        .contentShape(Rectangle())
                        .onTapGesture { guard isTop else { return }; editingText = true; DispatchQueue.main.async { editing = true } }
                }
            }
            .animation(.smooth(duration: 0.5), value: plan.text)
            .padding(.top, 20)
            .zIndex(1)   // the text, its selection handles and the edit menu stay above the calendar
                .onChange(of: plan.text) { old, new in
                    // The plan follows whatever you write where the place was, even if it isn't a real place:
                    // "Let's walk the Arb tonight!" → "Let's walk the hello tonight!" makes the plan "the hello".
                    let t = DeckCard.trackPlace(old: old, new: new, place: plan.place, span: placeSpan)
                    placeSpan = t.span
                    if let place = t.place {
                        if place != plan.place { plan.place = place }
                    } else if t.span == nil, let place = Near.find(in: new)?.name ?? Near.guess(in: new), place != plan.place {
                        plan.place = place   // couldn't find the place in the text: read the sentence instead
                    }
                }
            DayCalendar(plan: $plan, active: isTop, locked: $locked)
                .padding(.top, 40)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(isTop ? Color.white : Color(white: 0.914))
            .onTapGesture { hideKeyboard() })   // tap anywhere on the card outside the text to finish editing
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.black.opacity(Double(depth) * 0.18)).allowsHitTesting(false))
        .offset(x: dx)
        .rotationEffect(.degrees(Double(dx) / 30))
        .simultaneousGesture(isTop ? swipe : nil)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { g in
                guard !locked, abs(g.translation.width) > abs(g.translation.height) else { return }
                dx = g.translation.width
            }
            .onEnded { g in
                guard !locked else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { dx = 0 }; return }
                if dx > 100 { fly(1) } else if dx < -100 { fly(-1) }
                else { withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { dx = 0 } }
            }
    }

    /// Follows the place through edits by position. `span` is where the place sits (in characters); an edit that
    /// touches it becomes the new place, word for word, even if it isn't a real place. Returns the new place
    /// (nil to leave the plan alone) and the updated span.
    static func trackPlace(old: String, new: String, place: String, span: Range<Int>?) -> (place: String?, span: Range<Int>?) {
        let o = Array(old), n = Array(new)
        var s = span
        if let k = s, k.upperBound <= o.count,
       { let w = String(o[k]).trimmingCharacters(in: .whitespaces); return w.isEmpty || w.caseInsensitiveCompare(place) == .orderedSame }() {
        // still where we left it (or emptied out while you retype)
    } else {
            s = nil
            if let r = old.range(of: place, options: .caseInsensitive) {
                let lo = old.distance(from: old.startIndex, to: r.lowerBound)
                s = lo..<(lo + old.distance(from: r.lowerBound, to: r.upperBound))
            }
        }
        guard let sp = s else { return (nil, nil) }
        var cp = 0; while cp < min(o.count, n.count), o[cp] == n[cp] { cp += 1 }
        var cs = 0; while cs < min(o.count, n.count) - cp, o[o.count - 1 - cs] == n[n.count - 1 - cs] { cs += 1 }
        let delta = n.count - o.count, editEnd = o.count - cs
        if editEnd < sp.lowerBound { return (nil, (sp.lowerBound + delta)..<(sp.upperBound + delta)) }   // edit before it
        if cp > sp.upperBound { return (nil, sp) }                                                         // edit after it
        if cp < sp.lowerBound || editEnd > sp.upperBound { return (nil, nil) }   // a bigger rewrite: read the sentence instead
        let lo = min(sp.lowerBound, cp), hi = max(min(n.count, sp.upperBound + delta), n.count - cs)
        guard lo <= hi else { return (nil, nil) }
        let typed = String(n[lo..<hi]).trimmingCharacters(in: .whitespaces)
        return (typed.isEmpty ? nil : typed, lo..<hi)
    }

    private func fly(_ dir: CGFloat) {
        editing = false
        withAnimation(.easeIn(duration: 0.28)) { dx = dir * 520 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { onDecide(dir > 0) }
    }
}

// MARK: - The day: scrolls, tap the plan to flip to a new place, hold and drag it to change the time

struct DayCalendar: View {
    @Binding var plan: DeckPlan
    let active: Bool
    @Binding var locked: Bool

    static let h0 = 7.0, h1 = 24.0
    static let pxh: CGFloat = 64, padT: CGFloat = 16

    @State private var offset: CGFloat = 0
    @State private var scrollFrom: CGFloat?
    @State private var axisVertical: Bool?
    @State private var viewH: CGFloat = 0

    // plan block
    @State private var pressAt: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var lifted = false
    @State private var dragHour: Double?
    @State private var grab: CGFloat = 0
    @State private var fingerY: CGFloat = 0
    @State private var moved = false
    @State private var flipping = false
    @State private var angle: Double = 0
    @State private var shown: String?

    private let tick = Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect()

    private var gutter: CGFloat {
        let font = UIFont.systemFont(ofSize: 15, weight: .medium)
        let w = (Int(Self.h0)...Int(Self.h1)).map { (Fmt.hourLabel($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 40
        return ceil(w) + 16
    }
    private var contentH: CGFloat { Self.padT * 2 + CGFloat(Self.h1 - Self.h0) * Self.pxh }
    private func y(_ h: Double) -> CGFloat { Self.padT + CGFloat(h - Self.h0) * Self.pxh }
    private var hour: Double { dragHour ?? plan.startHour }
    private var clash: Bool { let h = hour, d = plan.duration; return plan.busy.contains { h < $0.upperBound && h + d > $0.lowerBound } }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                // hours
                ForEach(Int(Self.h0)...Int(Self.h1), id: \.self) { h in
                    Rectangle().fill(Color.black.opacity(0.07)).frame(width: w - gutter, height: 1)
                        .offset(x: gutter, y: y(Double(h)))
                    Text(Fmt.hourLabel(h)).font(.deckLabel).foregroundStyle(.black.opacity(0.4))
                        .frame(height: 20).offset(y: y(Double(h)) - 10)
                }
                // busy
                ForEach(Array(plan.busy.enumerated()), id: \.offset) { _, b in
                    let lo = max(b.lowerBound, Self.h0), hi = min(b.upperBound, Self.h1)
                    if hi > lo {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.949, green: 0.949, blue: 0.957))
                            .overlay(alignment: .leading) {
                                if hi - lo >= 0.75 { Text("Busy").font(.deckLabel).foregroundStyle(.black.opacity(0.35)).padding(.leading, 14) }
                            }
                            .frame(width: w - gutter, height: CGFloat(hi - lo) * Self.pxh - 9)
                            .offset(x: gutter, y: y(lo) + 5)
                    }
                }
                planBlock(width: w - gutter)
                    .offset(x: gutter, y: y(hour) + 5)
                    .zIndex(2)
            }
            .frame(width: w, height: contentH, alignment: .topLeading)
            .offset(y: -offset)
            .frame(width: w, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(name: "day")
            .contentShape(Rectangle())
            // fade the day out at the top and bottom; the mask reaches past the sides so a lifted plan isn't cut off
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                         .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom).padding(.horizontal, -24))
            .simultaneousGesture(scroll)
            .onTapGesture { hideKeyboard() }
            .onAppear { viewH = geo.size.height; center() }
            .onChange(of: geo.size.height) { _, h in viewH = h }
        }
        .onReceive(tick) { _ in autoScroll() }
    }

    // MARK: plan block

    private func planBlock(width: CGFloat) -> some View {
        HStack {
            Text(shown ?? plan.place).font(.deckLabel).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 8)
            if lifted {
                Text("\(Fmt.clock(hour)) – \(Fmt.clock(hour + plan.duration))").font(.deckLabel).foregroundStyle(.white.opacity(0.65))
                    .transition(.opacity)
            } else {
                Image(systemName: "dice").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: CGFloat(plan.duration) * Self.pxh - 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lifted && clash ? Color(red: 1, green: 0.231, blue: 0.188) : .black))
        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .scaleEffect(lifted ? 1.03 : 1)
        .shadow(color: .black.opacity(lifted ? 0.12 : 0), radius: 6, y: 4)
        .contentShape(Rectangle())
        .highPriorityGesture(active ? press : nil)
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("day"))
            .onChanged { g in
                if pressAt == nil {
                    pressAt = .now; moved = false; locked = true
                    grab = g.startLocation.y - (y(hour) + 5 - offset)   // where on the block you grabbed it
                    holdTask = Task { try? await Task.sleep(for: .seconds(0.3)); if !Task.isCancelled { lift() } }
                }
                fingerY = g.location.y                              // finger, in the day's visible frame
                if !lifted, hypot(g.translation.width, g.translation.height) > 6 { moved = true; lift() }
                if lifted { place() }
            }
            .onEnded { _ in
                holdTask?.cancel()
                let quick = !moved && Date.now.timeIntervalSince(pressAt ?? .now) < 0.25
                pressAt = nil
                if lifted { drop() } else { locked = false; if quick { flip() } }
            }
    }

    private func lift() {
        guard !lifted, !flipping else { return }
        holdTask?.cancel()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.smooth(duration: 0.3)) { lifted = true }
    }

    private func place() {
        let top = fingerY + offset - grab - 5
        var h = Self.h0 + Double((top - Self.padT) / Self.pxh)
        h = (h * 4).rounded() / 4
        h = max(Self.h0, min(Self.h1 - plan.duration, h))
        if h != dragHour {
            if dragHour != nil { UISelectionFeedbackGenerator().selectionChanged() }
            dragHour = h
        }
    }

    private func drop() {
        let ok = !clash
        withAnimation(.smooth(duration: 0.4)) {
            if ok, let h = dragHour { plan.move(toHour: h) }
            dragHour = nil
            lifted = false
        }
        if !ok { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        locked = false
    }

    private func autoScroll() {
        guard lifted, viewH > 0 else { return }
        let edge: CGFloat = 56
        var d: CGFloat = 0
        if fingerY < edge { d = -(edge - fingerY) / 6 } else if fingerY > viewH - edge { d = (fingerY - (viewH - edge)) / 6 }
        guard d != 0 else { return }
        offset = max(0, min(contentH - viewH, offset + d))
        place()
    }

    // MARK: flip to a new place (same motion as the sandbox: flip edge-on, swap, flip back, slowing down)

    private func flip() {
        guard !flipping else { return }
        flipping = true
        let next = Near.random(excluding: plan.place)
        let seq = (0..<5).map { _ in Near.random(excluding: plan.place).name } + [next.name]
        Task {
            for (k, name) in seq.enumerated() {
                let d = 0.07 + Double(k) * 0.045
                withAnimation(.easeIn(duration: d)) { angle = 90 }
                try? await Task.sleep(for: .seconds(d))
                shown = name
                angle = -90
                withAnimation(.easeOut(duration: d)) { angle = 0 }
                try? await Task.sleep(for: .seconds(d))
            }
            withAnimation(.smooth(duration: 0.5)) { plan.swapPlace(to: next.name) }   // text height eases if lines change
            shown = nil
            flipping = false
        }
    }

    // MARK: scrolling the day

    private var scroll: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                guard !lifted, pressAt == nil else { return }
                if axisVertical == nil { axisVertical = abs(g.translation.height) > abs(g.translation.width) }
                guard axisVertical == true else { return }
                if scrollFrom == nil { scrollFrom = offset }
                offset = clamp(scrollFrom! - g.translation.height)
            }
            .onEnded { g in
                defer { scrollFrom = nil; axisVertical = nil }
                guard axisVertical == true, let from = scrollFrom, !lifted else { return }
                withAnimation(.easeOut(duration: 0.45)) { offset = clamp(from - g.predictedEndTranslation.height) }
            }
    }
    private func clamp(_ o: CGFloat) -> CGFloat { max(0, min(contentH - viewH, o)) }
    private func center() {
        guard viewH > 0 else { return }
        offset = clamp(y(plan.startHour) + CGFloat(plan.duration) * Self.pxh / 2 - viewH / 2)
    }
}

/// Ends editing wherever the cursor is.
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
