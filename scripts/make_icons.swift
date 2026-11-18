// Regenerate workflow/icon.png and workflow/icons/*.png from SF Symbols
// (dev-only, macOS). The shipped workflow uses the committed PNGs.
//
//   swift scripts/make_icons.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("workflow")

// name: (SF Symbol, background RGB)
let icons: [(String, String, (CGFloat, CGFloat, CGFloat))] = [
  ("icon", "network", (0.20, 0.45, 0.85)),
  ("icons/lan", "cable.connector", (0.30, 0.55, 0.40)),
  ("icons/wifi", "wifi", (0.20, 0.45, 0.85)),
  ("icons/globe", "globe", (0.45, 0.35, 0.80)),
  ("icons/mac", "number", (0.40, 0.44, 0.50)),
  ("icons/warning", "exclamationmark.triangle.fill", (0.86, 0.45, 0.15)),
  ("icons/update", "arrow.down.circle.fill", (0.20, 0.60, 0.35)),
]

let size: CGFloat = 256
for (name, symbol, rgb) in icons {
  let img = NSImage(size: NSSize(width: size, height: size))
  img.lockFocus()
  NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: size - 20, height: size - 20),
               xRadius: 56, yRadius: 56).fill()
  let cfg = NSImage.SymbolConfiguration(pointSize: 140, weight: .medium)
    .applying(.init(paletteColors: [.white]))
  if let s = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(cfg) {
    let r = NSRect(x: (size - s.size.width) / 2, y: (size - s.size.height) / 2,
                   width: s.size.width, height: s.size.height)
    s.draw(in: r)
  } else {
    fatalError("unknown SF Symbol \(symbol)")
  }
  img.unlockFocus()
  let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
  try! rep.representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("\(name).png"))
  print("wrote \(name).png")
}
