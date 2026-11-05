import SwiftUI
import UIKit

// The final flow from the sandbox: Tonight → Reach out → You're all caught up.
// One card everywhere: avatar + name, the text big and editable in place, a round × to skip and a
// white Send. Swipe right to send, left to skip; the card flies off and the rest close up.

/// One person to text. Works for tonight's cards and reach-out people.
struct FlowItem: Identifiable, Equatable {
    let id: String
    let name: String
    let draft: String
}

struct FlowCard: View {
    let item: FlowItem
    var plan: String? = nil          // e.g. "Thu 7:00 PM · you're both free"
    let onSend: (String) -> Void
    let onSkip: () -> Void

    @State private var text = ""
    @State private var dx: CGFloat = 0
    @State private var leaving = false
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                FlowAvatar(name: item.name, size: 24)
                Text(item.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
            }

            // Edit in place: no box, just a cursor.
            TextField("", text: $text, axis: .vertical)
                .focused($editing)
                .font(.system(size: 22))
                .lineSpacing(4)
                .padding(.top, 16)

            if let plan {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    Text(plan)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 16)
            }

            HStack(spacing: 16) {
                Button { fly(-1) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel("Skip \(item.name)")
                Button { fly(1) } label: {
                    Text("Send")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
        .padding(24)
        .foregroundStyle(.white)
        .background(Color(red: 0.11, green: 0.11, blue: 0.118), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .offset(x: dx)
        .rotationEffect(.degrees(Double(dx) / 30))
        .opacity(leaving ? 0 : 1 - min(0.4, abs(Double(dx)) / 600))
        .gesture(
            DragGesture(minimumDistance: 16)
                .onChanged { g in
                    guard abs(g.translation.width) > abs(g.translation.height) else { return }
                    dx = g.translation.width
                }
                .onEnded { g in
                    if g.translation.width > 100 { fly(1) }
                    else if g.translation.width < -100 { fly(-1) }
                    else { withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { dx = 0 } }
                }
        )
        .onAppear { if text.isEmpty { text = item.draft } }
    }

    /// Slide off with a little tilt, then hand off so the list can close the gap.
    private func fly(_ dir: CGFloat) {
        editing = false
        withAnimation(.easeIn(duration: 0.25)) { dx = dir * 480; leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            if dir > 0 { onSend(text) } else { onSkip() }
        }
    }
}

struct FlowAvatar: View {
    let name: String
    let size: CGFloat
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.647, green: 0.663, blue: 0.706), Color(red: 0.490, green: 0.506, blue: 0.549)],
                                       startPoint: .top, endPoint: .bottom), in: Circle())
    }
}

/// Reach out step 1: just names. Gray until picked, white with a dot when picked.
struct ReachPicker: View {
    let people: [QuietPerson]
    @Binding var picked: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(people) { p in
                let on = picked.contains(p.id)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { if on { picked.remove(p.id) } else { picked.insert(p.id) } }
                } label: {
                    HStack {
                        Text(p.firstName).font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(on ? 1 : 0.35))
                        Spacer()
                        Circle().fill(.white).frame(width: 10, height: 10).scaleEffect(on ? 1 : 0.001)
                    }
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // Rows are 56 tall with the name centered; pull the list up so the first name sits where a
        // card's top edge would, 32 under the title like the cards.
        .padding(.top, -16)
    }
}

/// End of the night: the people you texted, middle face in front, and one way to keep going.
struct CaughtUpFaces: View {
    let names: [String]
    var body: some View {
        let shown = Array(names.prefix(3))
        HStack(spacing: -16) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, n in
                FlowAvatar(name: n, size: 64)
                    .background(Circle().fill(.black).padding(-4))
                    .zIndex(i == 1 ? 3 : (i == 0 ? 1 : 2))
            }
        }
    }
}

/// White, full-width bottom action used by the picker and the caught-up screen.
struct BottomCTA: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.25)
        .disabled(!enabled)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Entrance: a plain fade, no movement, blur or growing. Cards come in one at a time: each one
/// starts just as the one above it has mostly finished. Runs once.
private struct EaseIn: ViewModifier {
    let order: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(0.1 + Double(order) * 0.3)) { shown = true }
            }
    }
}

extension View {
    func easeIn(order: Int) -> some View { modifier(EaseIn(order: order)) }
}

// MARK: - Bottom edge blur (same recipe as the portfolio's .home-edge)
// Four stacked blurs that get stronger toward the edge (0.5 → 1 → 2 → 4px), each faded in over its own
// band, and no tint: cards just soften as they scroll off the bottom. 96pt tall.

/// A real backdrop blur with a dialed-down radius (a UIBlurEffect paused part-way via an animator),
/// masked to fade in from `from` to `to` (0 = top of the band, 1 = bottom).
struct EdgeBlurLayer: UIViewRepresentable {
    let amount: CGFloat      // 0...1 of the system blur; tiny values ≈ a few px
    let from: CGFloat
    let to: CGFloat
    var fromTop = false      // top edge: strongest at the top, fading out downward

    final class View: UIVisualEffectView {
        var animator: UIViewPropertyAnimator?
        let gradient = CAGradientLayer()
        override func layoutSubviews() {
            super.layoutSubviews()
            gradient.frame = bounds
        }
    }

    func makeUIView(context: Context) -> View {
        let v = View(effect: nil)
        v.isUserInteractionEnabled = false
        let anim = UIViewPropertyAnimator(duration: 1, curve: .linear) { v.effect = UIBlurEffect(style: .systemUltraThinMaterialDark) }
        anim.pausesOnCompletion = true
        anim.fractionComplete = amount
        v.animator = anim
        if fromTop {
            v.gradient.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
            v.gradient.locations = [NSNumber(value: Double(1 - to)), NSNumber(value: Double(1 - from))]
        } else {
            v.gradient.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
            v.gradient.locations = [NSNumber(value: Double(from)), NSNumber(value: Double(to))]
        }
        v.layer.mask = v.gradient
        return v
    }

    func updateUIView(_ v: View, context: Context) {
        v.animator?.fractionComplete = amount
    }

    static func dismantleUIView(_ v: View, coordinator: ()) {
        v.animator?.stopAnimation(true)
    }
}

struct EdgeBlur: View {
    var top = false
    var height: CGFloat = 96
    var body: some View {
        ZStack {
            if top {
                // Portfolio's top edge: tighter bands, a touch stronger at the very edge.
                EdgeBlurLayer(amount: 0.015, from: 0.00, to: 0.15, fromTop: true)
                EdgeBlurLayer(amount: 0.03, from: 0.10, to: 0.35, fromTop: true)
                EdgeBlurLayer(amount: 0.06, from: 0.25, to: 0.55, fromTop: true)
                EdgeBlurLayer(amount: 0.15, from: 0.45, to: 1.00, fromTop: true)
            } else {
                EdgeBlurLayer(amount: 0.015, from: 0.00, to: 0.30)
                EdgeBlurLayer(amount: 0.03, from: 0.25, to: 0.55)
                EdgeBlurLayer(amount: 0.06, from: 0.50, to: 0.80)
                EdgeBlurLayer(amount: 0.12, from: 0.75, to: 1.00)
            }
        }
        // Reach past the status bar / home-bar area to the screen's edge.
        .frame(height: height + (top ? 62 : 40))
        .offset(y: top ? -62 : 40)
        .allowsHitTesting(false)
    }
}
