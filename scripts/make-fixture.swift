import Foundation
import CoreGraphics
import ImageIO

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let context = CGContext(data: nil, width: 6000, height: 4000, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.12, green: 0.09, blue: 0.22, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 6000, height: 4000))
for index in 0..<20 {
    context.setFillColor(CGColor(red: CGFloat(index) / 25, green: 0.3, blue: 0.8, alpha: 1))
    context.fillEllipse(in: CGRect(x: index * 260 - 500, y: index * 130 - 400, width: 2200, height: 2200))
}
let first = folder.appendingPathComponent("photo_01.jpg")
let destination = CGImageDestinationCreateWithURL(first as CFURL, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("Fixture generation failed") }
for index in 2...24 { try FileManager.default.copyItem(at: first, to: folder.appendingPathComponent(String(format: "photo_%02d.jpg", index))) }
try "SortFlow 2.0 — test podglądu dokumentu".write(to: folder.appendingPathComponent("Przyklad.txt"), atomically: true, encoding: .utf8)
