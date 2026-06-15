import SwiftUI

/// Full-screen confetti burst shown alongside the achievement banner.
///
/// 50 particles fall from above the top edge to below the bottom edge, each with
/// its own sideways drift, duration, and start delay, fading out at the end of
/// the fall. Particle parameters live in @State so they are generated once per
/// view identity — parent re-renders never reshuffle particles mid-flight.
/// ContentView assigns a fresh identity per achievement so the burst replays
/// for each queued banner.
struct ConfettiView: View {
    private struct Particle: Identifiable {
        let id: Int
        let color: Color
        /// Horizontal position at the start/end of the fall, as a fraction of the
        /// container width. Ranges extend slightly past 0...1 so particles also
        /// drift in and out across the screen edges.
        let startXFraction: Double
        let endXFraction: Double
        let size: Double
        let duration: Double
        let delay: Double
    }

    @State private var particles: [Particle] = {
        let palette: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]
        return (0..<50).map { i in
            Particle(
                id: i,
                color: palette[i % palette.count],
                startXFraction: .random(in: -0.1...1.1),
                endXFraction: .random(in: -0.2...1.2),
                size: .random(in: 6...11),
                duration: .random(in: 2.0...3.5),
                delay: .random(in: 0...0.4)
            )
        }
    }()

    /// Flipped once in onAppear; every particle's animations key off this value.
    @State private var fall = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(
                            x: geo.size.width * (fall ? particle.endXFraction : particle.startXFraction),
                            y: fall ? geo.size.height + 30 : -30
                        )
                        // Animates the position change above — gravity-style ease-in fall.
                        .animation(.easeIn(duration: particle.duration).delay(particle.delay), value: fall)
                        // Fade out over the last 0.6 s of the fall, on its own timing.
                        // .opacity must sit BETWEEN the two .animation modifiers: each
                        // .animation only animates the modifiers above it. (The original
                        // bug: opacity came after the only .animation in the chain, so it
                        // snapped to 0 instantly and the whole burst played invisibly.)
                        .opacity(fall ? 0 : 1)
                        .animation(
                            .linear(duration: 0.6).delay(particle.delay + particle.duration - 0.6),
                            value: fall
                        )
                }
            }
        }
        .onAppear { fall = true }
    }
}

#Preview {
    ConfettiView()
}
