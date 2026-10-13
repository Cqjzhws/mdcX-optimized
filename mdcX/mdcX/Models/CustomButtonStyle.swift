//
//  CustomButtonStyle.swift
//  mdcX Max
//
//  2.3.0 - 深色玻璃拟态按钮，按压回弹时长跟随全局设置
//

import SwiftUI

struct CustomButtonStyle: ButtonStyle {
    var color: Color
    var foregroundColor: Color = .white
    var isDisabledStyle: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isDisabledStyle ? Color.white.opacity(0.08) : color)

                    if !isDisabledStyle {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    }
                }
            )
            .foregroundColor(isDisabledStyle ? Color.white.opacity(0.35) : foregroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(isDisabledStyle ? 0.05 : 0.14), lineWidth: 0.8)
            )
            .shadow(
                color: isDisabledStyle ? .clear : color.opacity(configuration.isPressed ? 0.12 : 0.3),
                radius: configuration.isPressed ? 2 : 7,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed && !isDisabledStyle ? 0.965 : 1.0)
            .animation(.easeOut(duration: AppSettings.shared.anim), value: configuration.isPressed)
    }
}
