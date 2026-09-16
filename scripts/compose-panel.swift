// Wraps a product screenshot in an App Store marketing panel.
//
// Direction "Forest": a deep green block carries the headline on the left, an oversized
// outlined numeral indexes the panel, and the screenshot bleeds off the right edge. Colours
// deliberately avoid the icon's amber, which read as too yellow at panel size.
//
// usage: compose-panel IN OUT INDEX "Headline" ["Subline"]
import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 5 else {
    FileHandle.standardError.write(Data("usage: IN OUT INDEX headline [subline]\n".utf8)); exit(2)
}
let index = args[3], headline = args[4]
let subline = args.count > 5 ? args[5] : ""

// Space Grotesk is not a system face; register the downloaded copy so the panels match the
// approved direction. Falls back to the system font if the file is missing.
let fontURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("design/fonts/SpaceGrotesk.ttf")
var haveGrotesk = false
if FileManager.default.fileExists(atPath: fontURL.path) {
    haveGrotesk = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
}
func face(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    if haveGrotesk {
        let name = weight >= .bold ? "SpaceGrotesk-Bold" : "SpaceGrotesk-Medium"
        if let f = NSFont(name: name, size: size) { return f }
        if let f = NSFont(name: "SpaceGrotesk", size: size) { return f }
    }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

let W = 2880, H = 1800
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let shot = CGImageSourceCreateImageAtIndex(src, 0, nil)!

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

let deep = NSColor(srgbRed: 0.043, green: 0.078, blue: 0.063, alpha: 1)    // #0b1410
let forest = NSColor(srgbRed: 0.078, green: 0.224, blue: 0.173, alpha: 1)  // #14392c
let mint = NSColor(srgbRed: 0.624, green: 0.839, blue: 0.706, alpha: 1)    // #9fd6b4
let paper = NSColor(srgbRed: 0.949, green: 0.969, blue: 0.953, alpha: 1)   // #f2f7f3

deep.setFill()
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

let blockW = CGFloat(W) * 0.45
forest.setFill()
ctx.fill(CGRect(x: 0, y: 0, width: blockW, height: CGFloat(H)))

// Oversized index numeral, outlined, bleeding off the block's bottom-right corner.
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: 0, width: blockW, height: CGFloat(H)))
let numeral = NSAttributedString(string: index, attributes: [
    .font: face(780, .bold),
    .foregroundColor: NSColor.clear,
    .strokeColor: mint.withAlphaComponent(0.22),
    .strokeWidth: 2.2,
])
numeral.draw(at: CGPoint(x: blockW - numeral.size().width + 96, y: -196))
ctx.restoreGState()

let margin: CGFloat = 118
let textW = blockW - margin * 2

func draw(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
          tracking: CGFloat = 0, at y: CGFloat) -> CGFloat {
    let p = NSMutableParagraphStyle()
    p.lineHeightMultiple = 0.98
    let a = NSAttributedString(string: s, attributes: [
        .font: face(size, weight), .foregroundColor: color,
        .kern: tracking, .paragraphStyle: p,
    ])
    let bounds = a.boundingRect(with: CGSize(width: textW, height: 2000),
                                options: [.usesLineFragmentOrigin, .usesFontLeading])
    a.draw(with: CGRect(x: margin, y: y - bounds.height, width: textW, height: bounds.height),
           options: [.usesLineFragmentOrigin, .usesFontLeading])
    return bounds.height
}

// Block text is vertically centred as a group.
let eyebrowH: CGFloat = 40, gap1: CGFloat = 46, gap2: CGFloat = 54
let headProbe = NSAttributedString(string: headline, attributes: [.font: face(102, .bold)])
    .boundingRect(with: CGSize(width: textW, height: 2000),
                  options: [.usesLineFragmentOrigin, .usesFontLeading]).height
let subProbe = subline.isEmpty ? 0 : NSAttributedString(string: subline, attributes: [.font: face(44, .medium)])
    .boundingRect(with: CGSize(width: textW, height: 2000),
                  options: [.usesLineFragmentOrigin, .usesFontLeading]).height
let groupH = eyebrowH + gap1 + headProbe + (subline.isEmpty ? 0 : gap2 + subProbe)
var cursor = (CGFloat(H) + groupH) / 2

_ = draw(index + " — TYTO", size: 30, weight: .medium, color: mint, tracking: 5.4, at: cursor)
cursor -= eyebrowH + gap1
_ = draw(headline, size: 102, weight: .bold, color: paper, tracking: -3.0, at: cursor)
cursor -= headProbe + gap2
if !subline.isEmpty {
    _ = draw(subline, size: 44, weight: .medium, color: paper.withAlphaComponent(0.56), at: cursor)
}

NSGraphicsContext.restoreGraphicsState()

// Screenshot bleeds off the right edge, rounded only on the leading corners.
let shotX = CGFloat(W) * 0.41
let shotW = CGFloat(W) - shotX + 260
let shotH = shotW * CGFloat(shot.height) / CGFloat(shot.width)
let shotRect = CGRect(x: shotX, y: (CGFloat(H) - shotH) / 2, width: shotW, height: shotH)
let r: CGFloat = 34
let clip = CGMutablePath()
clip.move(to: CGPoint(x: shotRect.minX + r, y: shotRect.minY))
clip.addLine(to: CGPoint(x: shotRect.maxX, y: shotRect.minY))
clip.addLine(to: CGPoint(x: shotRect.maxX, y: shotRect.maxY))
clip.addLine(to: CGPoint(x: shotRect.minX + r, y: shotRect.maxY))
clip.addArc(tangent1End: CGPoint(x: shotRect.minX, y: shotRect.maxY),
            tangent2End: CGPoint(x: shotRect.minX, y: shotRect.maxY - r), radius: r)
clip.addLine(to: CGPoint(x: shotRect.minX, y: shotRect.minY + r))
clip.addArc(tangent1End: CGPoint(x: shotRect.minX, y: shotRect.minY),
            tangent2End: CGPoint(x: shotRect.minX + r, y: shotRect.minY), radius: r)
clip.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: -14, height: -30), blur: 90,
              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.7))
ctx.addPath(clip); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(clip); ctx.clip()
ctx.draw(shot, in: shotRect)
ctx.restoreGState()

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("\(args[2]): \(W)x\(H)")
