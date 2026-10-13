import SpriteKit
import CoreGraphics

/// Procedural art: every texture is painted at launch with CoreGraphics, then SpriteKit derives
/// normal maps from them so SKLightNode torches cast real per-pixel lighting (the "remaster" look).
enum Art {
    static var cache: [String: SKTexture] = [:]
    /// Seeded visual-randomness stream for deterministic test/snapshot sessions (nil = system random).
    static var visRng: RNG?
    static func vrand(_ r: ClosedRange<CGFloat>) -> CGFloat {
        guard visRng != nil else { return CGFloat.random(in: r) }
        return r.lowerBound + (r.upperBound - r.lowerBound) * CGFloat(visRng!.unit())
    }

    /// Fast Sobel normal map from luminance (replaces SKTexture.generatingNormalMap, which is serial and slow).
    /// Thread-safe pure function; returns an RGBA image where rgb = packed normal.
    static func normalMap(from img: CGImage, strength: Double = 2.2) -> CGImage {
        let w = img.width, h = img.height
        var src = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        src.withUnsafeMutableBytes { buf in
            let c = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var lum = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { lum[i] = (0.3 * Float(src[i * 4]) + 0.59 * Float(src[i * 4 + 1]) + 0.11 * Float(src[i * 4 + 2])) / 255 }
        var out = [UInt8](repeating: 255, count: w * h * 4)
        @inline(__always) func L(_ x: Int, _ y: Int) -> Float { lum[min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))] }
        let s = Float(strength)
        for y in 0..<h {
            for x in 0..<w {
                let gx = (L(x + 1, y - 1) + 2 * L(x + 1, y) + L(x + 1, y + 1)) - (L(x - 1, y - 1) + 2 * L(x - 1, y) + L(x - 1, y + 1))
                let gy = (L(x - 1, y + 1) + 2 * L(x, y + 1) + L(x + 1, y + 1)) - (L(x - 1, y - 1) + 2 * L(x, y - 1) + L(x + 1, y - 1))
                var nx = -gx * s, ny = gy * s, nz: Float = 1
                let inv = 1 / (nx * nx + ny * ny + nz * nz).squareRoot()
                nx *= inv; ny *= inv; nz *= inv
                let o = (y * w + x) * 4
                out[o] = UInt8((nx * 0.5 + 0.5) * 255); out[o + 1] = UInt8((ny * 0.5 + 0.5) * 255); out[o + 2] = UInt8((nz * 0.5 + 0.5) * 255)
            }
        }
        return out.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }

    static func paint(_ key: String, _ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> SKTexture {
        if let t = cache[key] { return t }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        let t = SKTexture(cgImage: ctx.makeImage()!)
        t.filteringMode = .linear
        cache[key] = t
        return t
    }

    static func rgba(_ c: SKColor, _ a: CGFloat = 1) -> CGColor {
        let s = c.usingColorSpace(.deviceRGB) ?? c
        return CGColor(red: s.redComponent, green: s.greenComponent, blue: s.blueComponent, alpha: a)
    }

    /// Sandstone / palace masonry block, PoP2-style: offset bricks, chipped edges, mortar, grime.
    static func stone(_ base: SKColor, variant: Int) -> SKTexture {
        paint("stone\(variant)\(base.hash)", 128, 128) { c in
            var r = RNG(UInt64(variant) &+ 77)
            c.setFillColor(rgba(base.blended(withFraction: 0.55, of: .black)!)); c.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            let rows = 4
            // Each row's brick widths sum to exactly 128 so the texture tiles seamlessly.
            let patterns: [[CGFloat]] = [[64, 64], [48, 80], [80, 48], [32, 48, 48], [48, 48, 32], [40, 48, 40]]
            for row in 0..<rows {
                let y = CGFloat(row) * 32
                let widths = patterns[r.int(patterns.count)]
                var x: CGFloat = row % 2 == 0 ? 0 : -16
                for bw in widths + [widths[0]] {
                    defer { x += bw }
                    if x >= 128 { break }
                    let shade = CGFloat(r.unit()) * 0.22 - 0.11
                    let col = shade > 0 ? base.blended(withFraction: shade, of: .white)! : base.blended(withFraction: -shade, of: .black)!
                    let rect = CGRect(x: x + 2, y: y + 2, width: bw - 4, height: 28)
                    c.setFillColor(rgba(col)); c.fill(rect)
                    // bevel: lit top, dark bottom
                    c.setFillColor(CGColor(gray: 1, alpha: 0.07)); c.fill(CGRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2))
                    c.setFillColor(CGColor(gray: 0, alpha: 0.22)); c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2))
                    // pits, cracks
                    for _ in 0..<14 {
                        let px = rect.minX + CGFloat(r.unit()) * rect.width, py = rect.minY + CGFloat(r.unit()) * rect.height
                        c.setFillColor(CGColor(gray: r.chance(0.5) ? 0 : 1, alpha: 0.12)); c.fillEllipse(in: CGRect(x: px, y: py, width: 2 + CGFloat(r.int(3)), height: 2))
                    }
                    if r.chance(0.3) {
                        c.setStrokeColor(CGColor(gray: 0, alpha: 0.35)); c.setLineWidth(1)
                        var p = CGPoint(x: rect.minX + CGFloat(r.unit()) * rect.width, y: rect.maxY)
                        c.move(to: p)
                        for _ in 0..<4 { p = CGPoint(x: p.x + CGFloat(r.range(-6, 6)), y: p.y - CGFloat(r.range(4, 9))); c.addLine(to: p) }
                        c.strokePath()
                    }
                }
            }
            // grime gradient toward bottom
            let g = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.25)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 128), end: CGPoint(x: 0, y: 0), options: [])
        }
    }

    /// Back wall: much darker than the playfield, seamless 256 tiling (32px bricks: 256/32 = 8),
    /// with a deep pointed-arch alcove. Dark base is what lets torches create real light pools.
    static func backWall(_ base: SKColor) -> SKTexture {
        paint("back\(base.hash)", 256, 256) { c in
            let dark = base.blended(withFraction: 0.84, of: .black)!
            c.setFillColor(rgba(dark.blended(withFraction: 0.5, of: .black)!)); c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var r = RNG(5)
            for row in 0..<8 {
                var x: CGFloat = row % 2 == 0 ? 0 : -32
                while x < 256 {
                    let s = CGFloat(r.unit()) * 0.10
                    c.setFillColor(rgba(dark.blended(withFraction: s, of: .white)!))
                    c.fill(CGRect(x: x + 1.5, y: CGFloat(row) * 32 + 1.5, width: 61, height: 29))
                    c.setFillColor(CGColor(gray: 1, alpha: 0.05)); c.fill(CGRect(x: x + 1.5, y: CGFloat(row) * 32 + 28.5, width: 61, height: 2))
                    x += 64
                }
            }
            // Deep pointed (Persian) arch alcove: opaque black interior + lit stone frame
            let arch = CGMutablePath()
            arch.move(to: CGPoint(x: 100, y: 36)); arch.addLine(to: CGPoint(x: 100, y: 148))
            arch.addQuadCurve(to: CGPoint(x: 128, y: 196), control: CGPoint(x: 100, y: 180))
            arch.addQuadCurve(to: CGPoint(x: 156, y: 148), control: CGPoint(x: 156, y: 180))
            arch.addLine(to: CGPoint(x: 156, y: 36)); arch.closeSubpath()
            c.addPath(arch); c.setStrokeColor(rgba(base.blended(withFraction: 0.45, of: .black)!)); c.setLineWidth(10); c.strokePath()
            c.addPath(arch); c.setFillColor(CGColor(gray: 0.02, alpha: 1)); c.fillPath()
            c.saveGState(); c.addPath(arch); c.clip()
            let g = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 0, alpha: 0), rgba(base, 0.18)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 200), end: CGPoint(x: 0, y: 36), options: [])
            c.restoreGState()
            // sill
            c.setFillColor(rgba(base.blended(withFraction: 0.3, of: .black)!)); c.fill(CGRect(x: 92, y: 30, width: 72, height: 8))
        }
    }

    static func skyGradient(_ top: SKColor, _ bottom: SKColor) -> SKTexture {
        paint("sky\(top.hash)\(bottom.hash)", 4, 256) { c in
            let g = CGGradient(colorsSpace: nil, colors: [rgba(bottom), rgba(top)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
    }

    static var softGlow: SKTexture {
        paint("glow", 128, 128) { c in
            let g = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }

    static var vignette: SKTexture {
        paint("vig", 256, 256) { c in
            let g = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.85)] as CFArray, locations: [0.45, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 182, options: [.drawsAfterEndLocation])
        }
    }

    static var spark: SKTexture {
        paint("spark", 16, 16) { c in
            let g = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
        }
    }

    /// Torch with flame + embers emitters and a flickering SKLightNode (normal-mapped stone reacts).
    static func torch(light color: SKColor) -> SKNode {
        let n = SKNode()
        let bracket = SKSpriteNode(color: SKColor(white: 0.12, alpha: 1), size: CGSize(width: 8, height: 22))
        bracket.position = CGPoint(x: 0, y: -10); n.addChild(bracket)
        let flame = SKEmitterNode()
        flame.particleTexture = spark; flame.particleBirthRate = 70; flame.particleLifetime = 0.45; flame.particleLifetimeRange = 0.2
        flame.emissionAngle = .pi / 2; flame.emissionAngleRange = 0.4; flame.particleSpeed = 45; flame.particleSpeedRange = 20
        flame.particleScale = 0.9; flame.particleScaleRange = 0.4; flame.particleScaleSpeed = -1.6
        flame.particleColor = color; flame.particleColorBlendFactor = 1; flame.particleBlendMode = .add
        flame.particleAlpha = 0.9; flame.particleAlphaSpeed = -1.8; flame.particlePositionRange = CGVector(dx: 6, dy: 2)
        n.addChild(flame)
        let embers = SKEmitterNode()
        embers.particleTexture = spark; embers.particleBirthRate = 4; embers.particleLifetime = 2.2
        embers.emissionAngle = .pi / 2; embers.emissionAngleRange = 0.8; embers.particleSpeed = 60; embers.particleSpeedRange = 30
        embers.particleScale = 0.25; embers.particleColor = color; embers.particleColorBlendFactor = 1; embers.particleBlendMode = .add
        embers.particleAlphaSpeed = -0.4; embers.yAcceleration = 10
        n.addChild(embers)
        let halo = SKSpriteNode(texture: softGlow, size: CGSize(width: 220, height: 220))
        halo.color = color; halo.colorBlendFactor = 1; halo.alpha = 0.22; halo.blendMode = .add; n.addChild(halo)
        let light = SKLightNode()
        light.categoryBitMask = 1; light.lightColor = color; light.falloff = 1.6
        light.ambientColor = .clear; light.shadowColor = SKColor(white: 0, alpha: 0.5)
        n.addChild(light)
        let flicker = SKAction.customAction(withDuration: 0.12) { _, _ in
            let f = Art.vrand(1.35...1.8); light.falloff = f; halo.alpha = 0.16 + (1.8 - f) * 0.3
        }
        n.run(.repeatForever(.sequence([flicker, .wait(forDuration: 0.05)])))
        return n
    }
}
