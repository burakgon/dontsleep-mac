import AppKit

/// A look for the icon in the menu bar.
///
/// Each look is one shape in two forms: an outline while the Mac sleeps as usual, and the
/// same shape filled in while it is being kept awake. The two forms occupy exactly the same
/// place, so the icon never moves when the state changes; it only lights up. The menu bar
/// also dims the outline, the way macOS shows anything that is switched off.
///
/// All but one are system symbols, whose outlined and filled forms are drawn to match and
/// which have the weight and size of the icons around them. They are template images: they
/// take on the color of the menu bar by themselves.
enum IconStyle: String, CaseIterable {
    case lightBulb, coffeeCup, coffeeBean, bolt, flame, dot

    var title: String {
        switch self {
        case .lightBulb: "Light Bulb"
        case .coffeeCup: "Coffee Cup"
        case .coffeeBean: "Coffee Bean"
        case .bolt: "Bolt"
        case .flame: "Flame"
        case .dot: "Dot"
        }
    }

    /// The icon as it looks while the Mac is being kept awake (`isActive`), or while it is not.
    func image(isActive: Bool) -> NSImage {
        let description = isActive ? "DontSleep, on" : "DontSleep, off"
        let symbol: String
        switch self {
        case .lightBulb: symbol = "lightbulb"
        case .coffeeCup: symbol = "cup.and.saucer"
        case .bolt: symbol = "bolt"
        case .flame: symbol = "flame"
        case .dot: symbol = "circle"
        case .coffeeBean: return Self.coffeeBean(isFilled: isActive, description: description)
        }
        return NSImage(systemSymbolName: isActive ? symbol + ".fill" : symbol, accessibilityDescription: description) ?? NSImage()
    }

    /// The look that was chosen, kept in the preferences. A lit light bulb until one is.
    static var chosen: IconStyle {
        get { UserDefaults.standard.string(forKey: "MenuBarIcon").flatMap(IconStyle.init) ?? .lightBulb }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "MenuBarIcon") }
    }

    /// A coffee bean, which the system has no symbol for: an oval leaning to the right with
    /// the S-shaped crease down its length. Drawn in an 18 point square with the line
    /// weight of the system's symbols; outlined while off, solid while on.
    private static func coffeeBean(isFilled: Bool, description: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { @Sendable _ in
            let lineWidth: CGFloat = 1.4
            var lean = AffineTransform(translationByX: 9, byY: 9)
            lean.rotate(byDegrees: -40)
            let body = NSBezierPath(ovalIn: NSRect(x: -5.1, y: -7.2, width: 10.2, height: 14.4))
            let crease = NSBezierPath()
            crease.move(to: NSPoint(x: 0.5, y: 7))
            crease.curve(to: .zero, controlPoint1: NSPoint(x: -2.6, y: 5), controlPoint2: NSPoint(x: -2.2, y: 1.7))
            crease.curve(to: NSPoint(x: -0.5, y: -7), controlPoint1: NSPoint(x: 2.2, y: -1.7), controlPoint2: NSPoint(x: 2.6, y: -5))
            crease.lineCapStyle = .round
            body.transform(using: lean)
            crease.transform(using: lean)

            NSColor.black.set()
            if isFilled {
                body.fill()
                // The crease is cut out of the solid bean.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                crease.lineWidth = lineWidth * 1.2
                crease.stroke()
            } else {
                // Stroked at twice the width and clipped to the oval, the outline stays
                // inside the shape and so matches the solid bean in size.
                body.addClip()
                body.lineWidth = lineWidth * 2
                body.stroke()
                crease.lineWidth = lineWidth
                crease.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}
