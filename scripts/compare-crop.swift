// Compares a region of image A against image B pixel by pixel.
// usage: swift scripts/compare-crop.swift A.png B.png x y w h [inset]
import CoreGraphics
import Foundation
import ImageIO

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot load \(path)") }
    return img
}
func rgba(_ img: CGImage, _ rect: CGRect) -> [UInt8] {
    let w = Int(rect.width), h = Int(rect.height)
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    ctx.draw(img.cropping(to: rect)!, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}
let a = CommandLine.arguments
let A = load(a[1]), B = load(a[2])
let x = Int(a[3])!, y = Int(a[4])!, w = Int(a[5])!, h = Int(a[6])!
let inset = a.count > 7 ? Int(a[7])! : 0
let ra = rgba(A, CGRect(x: x + inset, y: y + inset, width: w - 2 * inset, height: h - 2 * inset))
let rb = rgba(B, CGRect(x: inset, y: inset, width: w - 2 * inset, height: h - 2 * inset))
var maxDiff = 0, sum = 0, bad = 0
for i in stride(from: 0, to: ra.count, by: 4) {
    var px = 0
    for c in 0..<3 { let d = abs(Int(ra[i + c]) - Int(rb[i + c])); px = max(px, d); sum += d }
    maxDiff = max(maxDiff, px)
    if px > 2 { bad += 1 }
}
let n = ra.count / 4
print("A: \(A.width)x\(A.height)  B: \(B.width)x\(B.height)  compared \(n) px (inset \(inset))")
print("max channel diff: \(maxDiff)   mean: \(String(format: "%.4f", Double(sum) / Double(n * 3)))   pixels differing >2: \(bad) (\(String(format: "%.3f", 100 * Double(bad) / Double(n)))%)")
