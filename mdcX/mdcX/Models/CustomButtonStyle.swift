//
//  CustomButtonStyle.swift
//  mdcX
//
//  Created by 이지안 on 5/10/25.
//

import SwiftUI

struct CustomButtonStyle: ButtonStyle {
    var color: Color
    var foregroundColor: Color = .white
    var isDisabledStyle: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isDisabledStyle ? Color.gray.opacity(0.35) : color)
                    
                    if !isDisabledStyle {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.25), Color.white.opacity(0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .foregroundColor(isDisabledStyle ? Color.gray.opacity(0.6) : foregroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isDisabledStyle ? 0 : 0.15), lineWidth: 1)
            )
            .shadow(
                color: isDisabledStyle ? .clear : color.opacity(configuration.isPressed ? 0.15 : 0.35),
                radius: configuration.isPressed ? 2 : 8,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed && !isDisabledStyle ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
