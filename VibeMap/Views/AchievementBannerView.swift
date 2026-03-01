//
//  AchievementBannerView.swift
//  VibeMap
//
//  Created by Jenna Jacquemyns on 22.02.2026.
//


import SwiftUI

struct AchievementBannerView: View {
    let achievement: Achievement
    var onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        VStack {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(achievement.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Image(systemName: achievement.icon)
                        .font(.title2)
                        .foregroundStyle(achievement.color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Achievement Unlocked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(achievement.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(achievement.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Dismiss button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.horizontal, 16)
            
            Spacer()
        }
        .offset(y: isVisible ? 0 : -200)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            // Slide in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isVisible = true
            }
            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                dismiss()
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.easeIn(duration: 0.3)) {
            isVisible = false
        }
        // Wait for animation to finish before removing from hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}