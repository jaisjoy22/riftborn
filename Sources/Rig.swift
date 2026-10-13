import SpriteKit

/// Articulated, rotoscope-style character rig (PoP2 looked rotoscoped; we get the same fluidity
/// from interpolated keyframe poses on a bone hierarchy). Root sits at the feet.
struct Pose {
    var torso: CGFloat = 0, head: CGFloat = 0, bodyY: CGFloat = 0, lean: CGFloat = 0
    var shF: CGFloat = -0.3, elF: CGFloat = 0.4, shB: CGFloat = 0.3, elB: CGFloat = 0.3
    var hipF: CGFloat = 0.1, knF: CGFloat = 0, hipB: CGFloat = -0.1, knB: CGFloat = 0
    var sword: CGFloat = -0.5

    static func lerp(_ a: Pose, _ b: Pose, _ t: CGFloat) -> Pose {
        func l(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return Pose(torso: l(a.torso, b.torso), head: l(a.head, b.head), bodyY: l(a.bodyY, b.bodyY), lean: l(a.lean, b.lean),
                    shF: l(a.shF, b.shF), elF: l(a.elF, b.elF), shB: l(a.shB, b.shB), elB: l(a.elB, b.elB),
                    hipF: l(a.hipF, b.hipF), knF: l(a.knF, b.knF), hipB: l(a.hipB, b.hipB), knB: l(a.knB, b.knB),
                    sword: l(a.sword, b.sword))
    }

    // Library (angles in radians; positive = counter-clockwise, character faces +x)
    static let idle = Pose()
    static let guardStance = Pose(torso: 0.05, shF: 0.9, elF: 0.5, shB: -0.4, elB: 1.2, hipF: 0.35, knF: -0.35, hipB: -0.35, knB: -0.2, sword: 0.15)
    static let windup = Pose(torso: 0.32, head: -0.1, lean: -4, shF: 2.5, elF: 0.7, shB: -0.8, elB: 1.0, hipF: 0.2, knF: -0.5, hipB: -0.55, knB: -0.4, sword: 1.2)
    static let strike = Pose(torso: -0.38, head: 0.2, lean: 10, shF: 1.35, elF: -0.05, shB: -1.2, elB: 0.4, hipF: 0.9, knF: -0.7, hipB: -0.75, knB: -0.1, sword: -0.08)
    static let heavyWindup = Pose(torso: 0.5, head: -0.2, bodyY: -4, lean: -6, shF: 3.0, elF: 0.4, shB: 2.6, elB: 0.6, hipF: 0.5, knF: -1.0, hipB: -0.5, knB: -0.6, sword: 1.6)
    static let heavyStrike = Pose(torso: -0.6, head: 0.25, bodyY: -8, lean: 14, shF: 0.4, elF: -0.1, shB: 0.3, elB: 0.1, hipF: 1.2, knF: -1.2, hipB: -0.9, knB: -0.1, sword: -0.9)
    static let recover = Pose(torso: -0.12, lean: 4, shF: 0.7, elF: 0.3, shB: -0.6, elB: 0.9, hipF: 0.5, knF: -0.5, hipB: -0.45, knB: -0.2, sword: -0.3)
    static let block = Pose(torso: 0.12, lean: -2, shF: 1.6, elF: 1.1, shB: 1.1, elB: 1.4, hipF: 0.4, knF: -0.5, hipB: -0.5, knB: -0.3, sword: 1.45)
    static let hurt = Pose(torso: 0.45, head: 0.4, lean: -8, shF: -0.6, elF: 0.8, shB: 0.8, elB: 0.5, hipF: -0.2, knF: -0.3, hipB: 0.3, knB: -0.4, sword: -1.2)
    static let jump = Pose(torso: -0.1, head: 0.1, shF: 2.2, elF: 0.6, shB: -0.9, elB: 0.6, hipF: 1.2, knF: -1.6, hipB: -0.2, knB: -1.1, sword: 0.6)
    static let fall = Pose(torso: 0.05, shF: 2.6, elF: 0.4, shB: 2.4, elB: 0.5, hipF: 0.5, knF: -0.5, hipB: -0.3, knB: -0.6, sword: 1.0)
    static let wallRun = Pose(torso: -0.25, head: 0.15, shF: 2.4, elF: 0.8, shB: -1.4, elB: 0.6, hipF: 1.5, knF: -1.4, hipB: 0.2, knB: -1.6, sword: -1.0)
    static let dash = Pose(torso: -0.7, head: 0.4, bodyY: -10, lean: 8, shF: -0.4, elF: 0.2, shB: -1.4, elB: 0.2, hipF: 1.3, knF: -1.6, hipB: -1.0, knB: -0.3, sword: -1.4)
    static let dead = Pose(torso: 1.45, head: 0.3, bodyY: -26, lean: -16, shF: 2.8, elF: 0.2, shB: 2.4, elB: 0.2, hipF: 1.2, knF: 0, hipB: 1.0, knB: 0, sword: 2.0)

    static func run(_ p: CGFloat) -> Pose {
        let s = sin(p), c = cos(p)
        return Pose(torso: -0.22, head: 0.12, bodyY: abs(c) * 3 - 2, lean: 3,
                    shF: -s * 1.0 - 0.1, elF: 0.9, shB: s * 1.0 - 0.1, elB: 0.9,
                    hipF: s * 0.95 + 0.15, knF: -max(0, -c) * 1.4 - 0.15, hipB: -s * 0.95 + 0.15, knB: -max(0, c) * 1.4 - 0.15,
                    sword: -0.9 - s * 0.3)
    }
    static func breathe(_ t: CGFloat) -> Pose { var p = Pose.guardStance; p.bodyY = sin(t * 2.2) * 1.2; p.shF += sin(t * 2.2) * 0.04; return p }
}

enum Weapon { case scimitar, glaive, claws, staff }

struct RigStyle {
    var skin: SKColor, cloth: SKColor, accent: SKColor, metal: SKColor
    var scale: CGFloat = 1, bulk: CGFloat = 1
    var weapon: Weapon = .scimitar
    var turban = true, cape = false, crouch: CGFloat = 0
}

final class Rig {
    let root = SKNode()
    private let pelvis = SKNode(), chest = SKNode(), head = SKSpriteNode()
    private let uaF = SKSpriteNode(), laF = SKSpriteNode(), uaB = SKSpriteNode(), laB = SKSpriteNode()
    private let ulF = SKSpriteNode(), llF = SKSpriteNode(), ulB = SKSpriteNode(), llB = SKSpriteNode()
    private let torsoSpr = SKSpriteNode(), sash = SKSpriteNode()
    let blade = SKSpriteNode()
    let trail = SKShapeNode()
    private var trailPts: [CGPoint] = []
    private var parts: [SKSpriteNode] = []
    var pose = Pose.idle
    let style: RigStyle
    let L: CGFloat  // limb unit

    init(_ s: RigStyle) {
        style = s
        L = 15 * s.scale
        let bk = s.bulk
        func limb(_ n: SKSpriteNode, _ w: CGFloat, _ h: CGFloat, _ col: SKColor) {
            n.texture = Rig.capsule; n.size = CGSize(width: w * bk, height: h); n.color = col; n.colorBlendFactor = 1
            n.anchorPoint = CGPoint(x: 0.5, y: 1); n.lightingBitMask = 1; parts.append(n)
        }
        // Legs
        limb(ulB, 8, L * 1.15, s.cloth.blended(withFraction: 0.3, of: .black)!); limb(llB, 7, L * 1.15, s.skin.blended(withFraction: 0.35, of: .black)!)
        limb(ulF, 8, L * 1.15, s.cloth); limb(llF, 7, L * 1.15, s.skin)
        // Arms
        limb(uaB, 6.5, L * 0.95, s.skin.blended(withFraction: 0.35, of: .black)!); limb(laB, 6, L * 0.9, s.skin.blended(withFraction: 0.35, of: .black)!)
        limb(uaF, 6.5, L * 0.95, s.skin); limb(laF, 6, L * 0.9, s.skin)
        torsoSpr.texture = Rig.capsule; torsoSpr.size = CGSize(width: 14 * bk, height: L * 1.55); torsoSpr.color = s.cloth
        torsoSpr.colorBlendFactor = 1; torsoSpr.anchorPoint = CGPoint(x: 0.5, y: 0); torsoSpr.lightingBitMask = 1; parts.append(torsoSpr)
        sash.texture = Rig.capsule; sash.size = CGSize(width: 15 * bk, height: 5); sash.color = s.accent; sash.colorBlendFactor = 1
        sash.position = CGPoint(x: 0, y: 3); sash.lightingBitMask = 1; parts.append(sash)
        head.texture = Rig.headTex(turban: s.turban); head.size = CGSize(width: 13 * s.scale, height: 15 * s.scale)
        head.color = s.skin; head.colorBlendFactor = 0.0; head.anchorPoint = CGPoint(x: 0.5, y: 0); head.lightingBitMask = 1; parts.append(head)

        // Hierarchy: root -> pelvis -> [legs, chest -> [arms, head]]
        root.addChild(pelvis)
        pelvis.addChild(ulB); ulB.addChild(llB); llB.position = CGPoint(x: 0, y: -L * 1.1)
        pelvis.addChild(ulF); ulF.addChild(llF); llF.position = CGPoint(x: 0, y: -L * 1.1)
        ulB.zPosition = -2; llB.zPosition = 0; ulF.zPosition = 2
        pelvis.addChild(chest); chest.addChild(torsoSpr); chest.addChild(sash)
        chest.addChild(uaB); uaB.position = CGPoint(x: 0, y: L * 1.4); uaB.zPosition = -3
        uaB.addChild(laB); laB.position = CGPoint(x: 0, y: -L * 0.9)
        chest.addChild(head); head.position = CGPoint(x: 1, y: L * 1.5); head.zPosition = 1
        chest.addChild(uaF); uaF.position = CGPoint(x: 0, y: L * 1.4); uaF.zPosition = 4
        uaF.addChild(laF); laF.position = CGPoint(x: 0, y: -L * 0.9)

        // Weapon in the front hand
        switch s.weapon {
        case .scimitar: blade.texture = Rig.scimitarTex; blade.size = CGSize(width: 10, height: 40 * s.scale)
        case .glaive: blade.texture = Rig.scimitarTex; blade.size = CGSize(width: 12, height: 56 * s.scale)
        case .staff: blade.texture = Rig.staffTex; blade.size = CGSize(width: 6, height: 50 * s.scale)
        case .claws: blade.texture = Rig.clawTex; blade.size = CGSize(width: 12, height: 18 * s.scale)
        }
        blade.color = s.metal; blade.colorBlendFactor = 0.5
        blade.anchorPoint = CGPoint(x: 0.5, y: 0.08); blade.position = CGPoint(x: 0, y: -L * 0.85); blade.zPosition = 1
        laF.addChild(blade)
        if s.weapon == .claws {   // second claw on back hand
            let c2 = SKSpriteNode(texture: Rig.clawTex, size: blade.size); c2.anchorPoint = blade.anchorPoint
            c2.position = blade.position; c2.color = s.metal; c2.colorBlendFactor = 0.5; laB.addChild(c2)
        }
        trail.strokeColor = .clear; trail.fillColor = SKColor(white: 1, alpha: 0.55); trail.blendMode = .add; trail.zPosition = 30
        // Rim/outline silhouette: a slightly larger dark copy of every limb behind the rig, so characters
        // read cleanly against busy masonry (the classic hand-drawn "keyline").
        pelvis.position = CGPoint(x: 0, y: L * 2.2)
        blade.size.width *= 1.35
        for p in parts { p.normalTexture = Rig.capsuleNormal; p.lightingBitMask = 1 }
        head.normalTexture = nil
        buildKeylines()
    }
    private var keylines: [SKSpriteNode] = []

    private func buildKeylines() {
        for p in parts where p !== sash {
            let k = SKSpriteNode(texture: p.texture, size: CGSize(width: p.size.width + 4, height: p.size.height + 4))
            k.anchorPoint = p.anchorPoint; k.color = SKColor(white: 0.03, alpha: 1); k.colorBlendFactor = 1
            k.zPosition = -20; k.alpha = 0.9
            k.position = CGPoint(x: 0, y: p.anchorPoint.y == 1 ? 2 : -2)
            p.addChild(k)
            keylines.append(k)
        }
    }

    var height: CGFloat { L * 4.4 }

    func apply(_ p: Pose, facing: CGFloat) {
        pose = p
        root.xScale = facing
        pelvis.position = CGPoint(x: p.lean * 0.4, y: L * 2.2 + p.bodyY - style.crouch)
        chest.zRotation = -p.torso - style.crouch * 0.02
        head.zRotation = -p.head
        uaF.zRotation = p.shF; laF.zRotation = p.elF
        uaB.zRotation = p.shB; laB.zRotation = p.elB
        ulF.zRotation = p.hipF; llF.zRotation = p.knF
        ulB.zRotation = p.hipB; llB.zRotation = p.knB
        blade.zRotation = p.sword - .pi / 2 + (style.weapon == .claws ? 0.6 : 0)
    }

    /// Sword trail: sample blade tip in world space while the swing is active.
    func updateTrail(active: Bool, in scene: SKNode, color: SKColor) {
        if !active && trailPts.isEmpty { if trail.path != nil { trail.path = nil }; return }   // idle fast-path
        if trail.parent == nil { scene.addChild(trail) }
        if active {
            let tip = blade.convert(CGPoint(x: 0, y: blade.size.height * 0.95), to: scene)
            let base = blade.convert(CGPoint(x: 0, y: blade.size.height * 0.35), to: scene)
            trailPts.append(tip); trailPts.append(base)
            if trailPts.count > 16 { trailPts.removeFirst(2) }
        } else if !trailPts.isEmpty { trailPts.removeFirst(min(2, trailPts.count)) }
        guard trailPts.count >= 4 else { trail.path = nil; return }
        let path = CGMutablePath()
        let tips = stride(from: 0, to: trailPts.count, by: 2).map { trailPts[$0] }
        let bases = stride(from: 1, to: trailPts.count, by: 2).map { trailPts[$0] }
        path.move(to: tips[0]); for p in tips.dropFirst() { path.addLine(to: p) }
        for p in bases.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        trail.path = path; trail.fillColor = color.withAlphaComponent(0.5)
    }

    /// White hit flash across every limb (only touches nodes when the value changes).
    private var lastFlash: CGFloat = -1
    func flash(_ amount: CGFloat) {
        let a = (amount * 20).rounded() / 20
        guard a != lastFlash else { return }
        lastFlash = a
        for p in parts { p.colorBlendFactor = 1; p.color = a > 0 ? baseColor(p).blended(withFraction: a, of: .white)! : baseColor(p) }
        head.colorBlendFactor = a
        head.color = .white
    }
    private func baseColor(_ p: SKSpriteNode) -> SKColor {
        if p === torsoSpr { return style.cloth }
        if p === sash { return style.accent }
        if p === ulF { return style.cloth }
        if p === ulB { return style.cloth.blended(withFraction: 0.3, of: .black)! }
        if p === laB || p === uaB || p === llB { return style.skin.blended(withFraction: 0.35, of: .black)! }
        return style.skin
    }

    // MARK: Textures

    /// Cylinder normal map for limbs: normals bend left/right across the width so torchlight wraps around arms/legs.
    static let capsuleNormal: SKTexture = {
        let w = 32, h = 64
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let u = (Double(x) + 0.5) / Double(w) * 2 - 1          // -1..1 across width
            let nx = u, nz = max(0, 1 - u * u).squareRoot()
            let o = (y * w + x) * 4
            px[o] = UInt8((nx * 0.5 + 0.5) * 255); px[o + 1] = 128; px[o + 2] = UInt8((nz * 0.5 + 0.5) * 255)
        } }
        let img = px.withUnsafeMutableBytes { b in
            CGContext(data: b.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
        return SKTexture(cgImage: img)
    }()

    static let capsule: SKTexture = Art.paint("capsule", 32, 64) { c in
        let r = CGRect(x: 2, y: 1, width: 28, height: 62)
        c.addPath(CGPath(roundedRect: r, cornerWidth: 13, cornerHeight: 13, transform: nil)); c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillPath()
        // cylindrical shading: lit left edge, shadowed right
        let g = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 0, alpha: 0.45)] as CFArray, locations: [0.3, 1])!
        c.saveGState(); c.addPath(CGPath(roundedRect: r, cornerWidth: 13, cornerHeight: 13, transform: nil)); c.clip()
        c.drawLinearGradient(g, start: CGPoint(x: 8, y: 0), end: CGPoint(x: 30, y: 0), options: [])
        c.setFillColor(CGColor(gray: 1, alpha: 0.25)); c.fill(CGRect(x: 7, y: 6, width: 4, height: 52))
        c.restoreGState()
    }

    static func headTex(turban: Bool) -> SKTexture {
        Art.paint("head\(turban)", 32, 36) { c in
            c.setFillColor(CGColor(red: 0.82, green: 0.62, blue: 0.45, alpha: 1)); c.fillEllipse(in: CGRect(x: 4, y: 2, width: 24, height: 26))
            c.setFillColor(CGColor(gray: 0, alpha: 0.25)); c.fillEllipse(in: CGRect(x: 16, y: 2, width: 12, height: 24))
            c.setFillColor(CGColor(gray: 0.05, alpha: 1)); c.fill(CGRect(x: 22, y: 15, width: 4, height: 3))   // eye
            if turban {
                c.setFillColor(CGColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1)); c.fillEllipse(in: CGRect(x: 2, y: 17, width: 28, height: 17))
                c.setStrokeColor(CGColor(gray: 0, alpha: 0.2)); c.setLineWidth(1.5)
                for i in 0..<3 { c.move(to: CGPoint(x: 4, y: 20 + i * 4)); c.addLine(to: CGPoint(x: 28, y: 24 + i * 3)) }
                c.strokePath()
                c.setFillColor(CGColor(red: 0.85, green: 0.12, blue: 0.2, alpha: 1)); c.fillEllipse(in: CGRect(x: 20, y: 26, width: 6, height: 6))
            } else {
                c.setFillColor(CGColor(gray: 0.15, alpha: 1)); c.fillEllipse(in: CGRect(x: 2, y: 16, width: 28, height: 16))   // helm
                c.setFillColor(CGColor(gray: 0.6, alpha: 1)); c.fill(CGRect(x: 4, y: 14, width: 24, height: 3))
            }
        }
    }

    static let scimitarTex: SKTexture = Art.paint("scimitar", 24, 96) { c in
        c.setFillColor(CGColor(red: 0.55, green: 0.4, blue: 0.15, alpha: 1)); c.fill(CGRect(x: 9, y: 0, width: 6, height: 16))     // hilt
        c.setFillColor(CGColor(red: 0.9, green: 0.75, blue: 0.3, alpha: 1)); c.fill(CGRect(x: 2, y: 15, width: 20, height: 4))     // guard
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 8, y: 19)); p.addQuadCurve(to: CGPoint(x: 20, y: 95), control: CGPoint(x: 4, y: 70))
        p.addQuadCurve(to: CGPoint(x: 16, y: 19), control: CGPoint(x: 18, y: 55)); p.closeSubpath()
        c.addPath(p); c.setFillColor(CGColor(red: 0.85, green: 0.9, blue: 0.95, alpha: 1)); c.fillPath()
        c.setStrokeColor(CGColor(gray: 1, alpha: 0.9)); c.setLineWidth(1)
        c.move(to: CGPoint(x: 9, y: 22)); c.addQuadCurve(to: CGPoint(x: 19, y: 92), control: CGPoint(x: 6, y: 70)); c.strokePath()
    }
    static let staffTex: SKTexture = Art.paint("staff", 12, 96) { c in
        c.setFillColor(CGColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1)); c.fill(CGRect(x: 4, y: 0, width: 4, height: 84))
        c.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)); c.fillEllipse(in: CGRect(x: 0, y: 82, width: 12, height: 12))
    }
    static let clawTex: SKTexture = Art.paint("claw", 24, 36) { c in
        for i in 0..<3 {
            let p = CGMutablePath(); let x = CGFloat(2 + i * 7)
            p.move(to: CGPoint(x: x, y: 0)); p.addQuadCurve(to: CGPoint(x: x + 9, y: 34), control: CGPoint(x: x - 2, y: 24)); p.addLine(to: CGPoint(x: x + 5, y: 0))
            c.addPath(p)
        }
        c.setFillColor(CGColor(red: 0.9, green: 0.85, blue: 0.7, alpha: 1)); c.fillPath()
    }
}
