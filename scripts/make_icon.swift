import AppKit
import Foundation

// App 图标：深靛紫底上一颗发光的声球，右边一根绿色光标（声音变成字）。
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let inset: CGFloat = 60
let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)

NSGraphicsContext.saveGraphicsState()
shape.addClip()
// 底色：左上偏亮的靛紫，往右下沉成深夜色。
NSGradient(colors: [color(0x3A2F8F), color(0x0E0C24)])!
    .draw(fromCenter: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY - rect.height * 0.1), radius: 0,
          toCenter: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY - rect.height * 0.1), radius: rect.width * 1.1,
          options: [.drawsAfterEndingLocation])

// 声球后面的光晕
let orbCenter = NSPoint(x: rect.midX - 70, y: rect.midY)
let orbRadius: CGFloat = 230
NSGradient(colors: [color(0x7864FF, 0.55), color(0x7864FF, 0)])!
    .draw(fromCenter: orbCenter, radius: 0, toCenter: orbCenter, radius: orbRadius * 1.9, options: [])

// 光标后面的光
let caretRect = NSRect(x: rect.midX + 230, y: rect.midY - 210, width: 46, height: 420)
NSGradient(colors: [color(0x4ADE9B, 0.45), color(0x4ADE9B, 0)])!
    .draw(fromCenter: NSPoint(x: caretRect.midX, y: caretRect.midY), radius: 0,
          toCenter: NSPoint(x: caretRect.midX, y: caretRect.midY), radius: 170, options: [])
NSGraphicsContext.restoreGraphicsState()

// 声球：左上的高光 → 浅紫 → 靛紫 → 深紫
let orb = NSBezierPath(ovalIn: NSRect(x: orbCenter.x - orbRadius, y: orbCenter.y - orbRadius, width: orbRadius * 2, height: orbRadius * 2))
NSGraphicsContext.saveGraphicsState()
orb.addClip()
let highlight = NSPoint(x: orbCenter.x - orbRadius * 0.32, y: orbCenter.y + orbRadius * 0.44)
NSGradient(colorsAndLocations: (.white, 0), (color(0xCFC4FF), 0.16), (color(0x6E5BFF), 0.52), (color(0x1E1660), 1))!
    .draw(fromCenter: highlight, radius: 0, toCenter: highlight, radius: orbRadius * 1.45, options: [.drawsAfterEndingLocation])
NSGraphicsContext.restoreGraphicsState()

// 光标
let caret = NSBezierPath(roundedRect: caretRect, xRadius: 23, yRadius: 23)
color(0x4ADE9B).setFill()
caret.fill()

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("icon render failed\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote", output)
