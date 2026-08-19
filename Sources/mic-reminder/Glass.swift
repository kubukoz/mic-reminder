import AppKit

// Liquid Glass (macOS 26) helpers.
//
// The app is built against the macOS 26 SDK, so system-drawn chrome (menus,
// window frames, standard controls) already picks up the new material for
// free. What doesn't come for free is the *content* we lay out ourselves —
// the popover bodies and the Preferences window — so these helpers wrap that
// content in real NSGlassEffectViews when the OS supports them, and fall back
// to plain/NSVisualEffectView layouts everywhere else.
enum Glass {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static let cornerRadius: CGFloat = 16

    /// Wraps `content` in glass, pinned with `padding` on all sides.
    ///
    /// On macOS 26 this is an NSGlassEffectView; earlier systems get an
    /// NSVisualEffectView with the same geometry so callers don't have to
    /// branch on their own layout.
    static func wrap(
        _ content: NSView,
        padding: CGFloat = 0,
        cornerRadius: CGFloat = Glass.cornerRadius,
        tint: NSColor? = nil,
        style: Style = .regular
    ) -> NSView {
        let host = padded(content, by: padding)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.cornerRadius = cornerRadius
            glass.tintColor = tint
            glass.style = style.appKitStyle
            glass.contentView = host
            return glass
        }

        let fallback = NSVisualEffectView()
        fallback.translatesAutoresizingMaskIntoConstraints = false
        fallback.material = .popover
        fallback.blendingMode = .behindWindow
        fallback.state = .active
        fallback.wantsLayer = true
        fallback.layer?.cornerRadius = cornerRadius
        fallback.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        fallback.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: fallback.topAnchor),
            host.bottomAnchor.constraint(equalTo: fallback.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
        ])
        return fallback
    }

    /// Groups sibling glass views so that ones sitting within `spacing` of
    /// each other render as a single merged blob rather than separate panes.
    /// Also batches them into one render pass. No-op before macOS 26.
    static func container(_ content: NSView, spacing: CGFloat = 20) -> NSView {
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.spacing = spacing
            container.contentView = content
            return container
        }
        return content
    }

    /// Gives a button the glass bezel on macOS 26, leaving it alone before that.
    static func style(_ button: NSButton, prominent: Bool = false) {
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
        }
        if prominent {
            button.controlSize = .large
            button.bezelColor = .controlAccentColor
        }
    }

    enum Style {
        case regular
        case clear

        @available(macOS 26.0, *)
        var appKitStyle: NSGlassEffectView.Style {
            switch self {
            case .regular: return .regular
            case .clear: return .clear
            }
        }
    }

    /// Wraps `view` in a container that insets it by `padding` on all sides.
    private static func padded(_ view: NSView, by padding: CGFloat) -> NSView {
        guard padding > 0 else { return view }
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor, constant: padding),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -padding),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: padding),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -padding),
        ])
        return host
    }
}
