//
//  ConfettiView.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 08.02.2026.
//


import SwiftUI

struct ConfettiView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            ForEach(0..<50) { index in
                ConfettiParticle(index: index, animate: $animate)
            }
        }
        .onAppear {
            animate = true
        }
    }
}

struct ConfettiParticle: View {
    let index: Int
    @Binding var animate: Bool
    
    // Randomize properties for each particle
    let colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]
    let startX: Double = Double.random(in: -0.5...1.5)
    let endX: Double = Double.random(in: -0.5...1.5)
    let rotation: Double = Double.random(in: 0...360)
    let duration: Double = Double.random(in: 2.0...3.5)
    
    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(colors.randomElement()!)
                .frame(width: 8, height: 8)
                .position(x: geo.size.width * startX, y: -20)
                .rotationEffect(.degrees(rotation))
                .modifier(ParticleModifier(
                    animate: animate,
                    endX: geo.size.width * endX,
                    endY: geo.size.height + 20,
                    duration: duration,
                    index: index
                ))
        }
    }
}

struct ParticleModifier: AnimatableModifier {
    var animate: Bool
    let endX: Double
    let endY: Double
    let duration: Double
    let index: Int
    
    var animatableData: Double {
        get { animate ? 1 : 0 }
        set { _ = newValue }
    }
    
    func body(content: Content) -> some View {
        content
            .offset(x: animate ? (endX - (UIScreen.main.bounds.width * 0.5)) : 0, 
                    y: animate ? endY : 0)
            .animation(Animation.linear(duration: duration).repeatCount(1, autoreverses: false), value: animate)
            .opacity(animate ? 0 : 1) // Fade out at the end
    }
}