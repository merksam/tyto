// Crops a region from a screenshot and scales it to an exact App Store size.
// usage: swift scripts/crop-screenshot.swift IN OUT X Y W H [OUTW OUTH]
// Output is flattened onto opaque white: the App Store rejects alpha channels.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 7 else { FileHandle.standardError.write(Data("usage: IN OUT X Y W H [OUTW OUTH]\n".utf8)); exit(2) }
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let (x, y, w, h) = (Int(a[3])!, Int(a[4])!, Int(a[5])!, Int(a[6])!)
let outW = a.count > 7 ? Int(a[7])! : w
let outH = a.count > 8 ? Int(a[8])! : h

guard let cropped = img.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
    FileHandle.standardError.write(Data("crop outside image bounds\n".utf8)); exit(1)
}
let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
ctx.interpolationQuality = .high
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("\(a[2]): \(outW)x\(outH)")
