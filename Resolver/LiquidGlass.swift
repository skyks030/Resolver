import SwiftUI

// MARK: - Liquid Glass
//
// Apple's Liquid Glass material (introduced with macOS 26 "Tahoe") is applied here to the
// app's floating chrome — toolbars, popovers, overlays and controls — via `.glassEffect(...)`
// and the `.glass` / `.glassProminent` button styles.
//
// These are progressive-enhancement wrappers: on macOS 26+ they use the real Liquid Glass
// APIs; on older systems (this app's deployment target is 13.5) they fall back to the
// `.ultraThinMaterial` / bordered styling the app already used, so nothing regresses for
// users on an older OS.

extension View {

    /// Floating panel / toolbar background (header bars, popovers, overlay cards).
    @ViewBuilder
    func liquidGlassPanel(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if let tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        }
    }

    /// Same as `liquidGlassPanel`, but edge-to-edge with square corners — for full-width
    /// toolbars/header rows that sit flush against the window edge.
    @ViewBuilder
    func liquidGlassBar(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: Rectangle())
            } else {
                self.glassEffect(.regular, in: Rectangle())
            }
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    /// Pill-shaped glass background (badges, capsule labels).
    @ViewBuilder
    func liquidGlassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: Capsule())
            } else {
                self.glassEffect(.regular, in: Capsule())
            }
        } else {
            self.background(Capsule().fill(.ultraThinMaterial))
        }
    }

    /// Standard button styling using Liquid Glass on macOS 26+, falling back to the
    /// system bordered styles pre-26.
    @ViewBuilder
    func liquidGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

/// Wraps content in a `GlassEffectContainer` on macOS 26+ so sibling glass elements
/// (e.g. a row of toolbar buttons) merge/morph together the way Apple's Liquid Glass
/// controls do. Falls back to a plain `HStack`/passthrough otherwise.
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
