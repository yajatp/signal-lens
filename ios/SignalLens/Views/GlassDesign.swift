import SwiftUI

// A gorgeous, slow-animating liquid-neon background for the "iOS 27" vibe
struct GlassBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            // Base dark elegant space color
            Color(red: 0.03, green: 0.03, blue: 0.09)
                .ignoresSafeArea()
            
            // Neon glowing blob 1
            Circle()
                .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: animate ? 100 : -100, y: animate ? -160 : -40)
                .opacity(0.35)
            
            // Neon glowing blob 2
            Circle()
                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: animate ? -120 : 80, y: animate ? 120 : 220)
                .opacity(0.3)
            
            // Neon glowing blob 3
            Circle()
                .fill(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: animate ? -60 : 60, y: animate ? -60 : 60)
                .opacity(0.2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var glowColor: Color = .blue
    
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    
                    // Moving sheen
                    LinearGradient(
                        colors: [
                            .white.opacity(0.12),
                            .clear,
                            glowColor.opacity(0.06),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.4),
                                .white.opacity(0.1),
                                .clear,
                                glowColor.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            .shadow(color: glowColor.opacity(0.12), radius: 15, x: 0, y: 8)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 20, glowColor: Color = .blue) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, glowColor: glowColor))
    }
}

// Reusable glass card
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var glowColor: Color = .blue
    let content: Content
    
    init(cornerRadius: CGFloat = 20, glowColor: Color = .blue, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.glowColor = glowColor
        self.content = content()
    }
    
    var body: some View {
        content
            .liquidGlass(cornerRadius: cornerRadius, glowColor: glowColor)
    }
}

// Reusable section header
struct GlassSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title.uppercased())
            .font(.caption.bold())
            .tracking(1.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// Gorgeous glass button style
struct GlassButtonStyle: ButtonStyle {
    var color: Color = .blue
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.bold())
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(configuration.isPressed ? 0.45 : 0.6),
                                color.opacity(configuration.isPressed ? 0.25 : 0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: color.opacity(0.25), radius: configuration.isPressed ? 4 : 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Custom Glass Text Field container
struct GlassTextField: View {
    var title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.25), lineWidth: 0.8)
                )
        }
    }
}
