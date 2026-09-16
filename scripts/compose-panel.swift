// Wraps a product screenshot in an App Store marketing panel: branded background, a headline
// stating the benefit, and the shot inset with a shadow.
//
// Every shipping screenshot app does this (Monosnap, Snagit); a bare crop sells nothing.
// usage: swift scripts/compose-panel.swift IN OUT "Headline" ["Subline"]
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: IN OUT headline [subline]\n".utf8)); exit(2)
}
let headline = args[3]
let subline = args.count > 4 ? args[4] : ""

let W = 2880, H = 1800
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let shot = CGImageSourceCreateImageAtIndex(src, 0, nil)!

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ns

// Background: the icon's dusk palette, so the listing and the icon read as one product.
let bg = NSGradient(colors: [NSColor(srgbRed: 0.17, green: 0.20, blue: 0.34, alpha: 1),
                             NSColor(srgbRed: 0.07, green: 0.08, blue: 0.14, alpha: 1)])!
bg.draw(in: CGRect(x: 0, y: 0, width: W, height: H), angle: -90)
ctx.saveGState()
ctx.setBlendMode(.plusLighter)
// Drawn across the whole canvas: a radial gradient confined to a sub-rect leaves a visible
// rectangular seam where the fill stops.
NSGradient(colors: [NSColor(white: 1, alpha: 0.06), NSColor(white: 1, alpha: 0)])!
    .draw(in: CGRect(x: 0, y: 0, width: W, height: H),
          relativeCenterPosition: CGPoint(x: -0.45, y: 0.35))
ctx.restoreGState()

func draw(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
    guard !s.isEmpty else { return }
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
    ]
    NSAttributedString(string: s, attributes: attrs).draw(at: p)
}

// Text sits at the top; NSGraphicsContext here is not flipped, so y counts up from the bottom.
let margin: CGFloat = 190
draw(headline, at: CGPoint(x: margin, y: CGFloat(H) - 195), size: 82, weight: .bold, alpha: 1)
draw(subline, at: CGPoint(x: margin, y: CGFloat(H) - 285), size: 42, weight: .regular, alpha: 0.62)

// Product shot: fit the remaining area, rounded, with a shadow to lift it off the background.
let topUsed: CGFloat = subline.isEmpty ? 300 : 380
let available = CGSize(width: CGFloat(W) - margin * 2, height: CGFloat(H) - topUsed - 150)
let aspect = CGFloat(shot.width) / CGFloat(shot.height)
var shotSize = CGSize(width: available.width, height: available.width / aspect)
if shotSize.height > available.height {
    shotSize = CGSize(width: available.height * aspect, height: available.height)
}
let shotRect = CGRect(x: (CGFloat(W) - shotSize.width) / 2,
                      y: 150 + (available.height - shotSize.height) / 2,
                      width: shotSize.width, height: shotSize.height)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 60,
              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
NSColor.black.setFill()
NSBezierPath(roundedRect: shotRect, xRadius: 26, yRadius: 26).fill()
ctx.restoreGState()

ctx.saveGState()
NSBezierPath(roundedRect: shotRect, xRadius: 26, yRadius: 26).addClip()
ctx.draw(shot, in: shotRect)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("\(args[2]): \(W)x\(H)")
