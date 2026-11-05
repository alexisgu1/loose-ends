import SwiftUI

/// One send's worth of emoji confetti: two volleys from the bottom corners.
struct ConfettiBurst: Identifiable, Equatable {
    let id = UUID()
    let start = Date.now
    let emojis: [String]
}

/// Corner cannons: 20 emojis (12, then 8 a beat later), 32–48pt, popping in, arcing up and falling out.
struct ConfettiLayer: View {
    @Binding var bursts: [ConfettiBurst]

    private struct Piece {
        let emoji: String, left: Bool, delay: Double, angle: Double, speed: Double, spin: Double, size: Double, life: Double
    }
    private func pieces(_ b: ConfettiBurst) -> [Piece] {
        var rng = SeededRandom(seed: UInt64(abs(b.id.hashValue)))
        return (0..<20).map { i in
            let left = i % 2 == 0
            let a = left ? -55 - rng.next() * 30 : -125 + rng.next() * 30
            return Piece(emoji: b.emojis[i % max(1, b.emojis.count)], left: left, delay: i < 12 ? 0 : 0.22,
                         angle: a * .pi / 180, speed: 1050 + rng.next() * 450, spin: (rng.next() - 0.5) * 900,
                         size: 32 + rng.next() * 16, life: 2 + rng.next() * 0.5)
        }
    }

    var body: some View {
        TimelineView(.animation(paused: bursts.isEmpty)) { ctx in
            Canvas { g, size in
                // the sandbox physics were tuned on a 402×874 phone; scale to this screen
                let k = size.width / 402
                for b in bursts {
                    for p in pieces(b) {
                        let t = ctx.date.timeIntervalSince(b.start) - p.delay
                        guard t >= 0, t <= p.life else { continue }
                        let x0 = p.left ? -10.0 : 412.0, y0 = 880.0
                        let x = x0 + cos(p.angle) * p.speed * t
                        let y = y0 + sin(p.angle) * p.speed * t + 0.5 * 1250 * t * t
                        let pop = t < 0.03 ? 0.4 : t < 0.07 ? 1.25 : t < 0.1 ? 1.1 : 1
                        let fade = t > p.life * 0.8 ? 1 - (t - p.life * 0.8) / (p.life * 0.2) : 1
                        var c = g
                        c.opacity = fade
                        c.translateBy(x: x * k, y: y * k * (size.height / (874 * k)))
                        c.rotate(by: .degrees(p.spin * t / p.life))
                        c.scaleBy(x: pop, y: pop)
                        c.draw(Text(p.emoji).font(.system(size: p.size * k)), at: .zero)
                    }
                }
            }
        }
        .onChange(of: bursts) { _, list in
            guard let last = list.last else { return }
            let id = last.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { bursts.removeAll { $0.id == id } }
        }
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}
