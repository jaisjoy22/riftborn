import SpriteKit

enum Tile: UInt8 { case empty = 0, solid, spike, ledge /* one-way platform */ }

struct Spawn { enum Kind { case enemy, wanderer, shrine, chest } ; let kind: Kind; let x: Int; let y: Int }

/// Procedural dungeon: a chain of rooms laid out in a winding path (Prince of Persia verticality,
/// Diablo-style branching), with one-way ledges, spike pits, shrines, and a portal at the end.
final class World {
    let w: Int, h: Int
    var g: [Tile]
    var spawns: [Spawn] = []
    var start = (x: 3, y: 3)
    var portal = (x: 0, y: 0)

    init(seed: UInt64, depth: Int) {
        var r = RNG(seed &+ UInt64(depth) &* 7919)
        let rooms = 7 + min(depth, 10)
        w = 26 * 6; h = 22 * 4
        g = Array(repeating: .solid, count: w * h)
        // Room grid 6 x 4, random walk from left-bottom
        var cells: [(Int, Int)] = [(0, 0)]
        var visited: Set<Int> = [0]
        var cx = 0, cy = 0
        while cells.count < rooms {
            let dirs = [(1, 0), (1, 0), (0, 1), (0, -1), (-1, 0)]
            let d = r.pick(dirs)
            let nx = cx + d.0, ny = cy + d.1
            guard nx >= 0, nx < 6, ny >= 0, ny < 4 else { continue }
            cx = nx; cy = ny
            let key = ny * 6 + nx
            if !visited.contains(key) { visited.insert(key); cells.append((nx, ny)) }
        }
        let rw = 26, rh = 22
        func carve(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ t: Tile = .empty) {
            for y in max(1, y0)...min(h - 2, y1) { for x in max(1, x0)...min(w - 2, x1) { g[y * w + x] = t } }
        }
        for (i, c) in cells.enumerated() {
            let ox = c.0 * rw, oy = c.1 * rh
            carve(ox + 2, oy + 2, ox + rw - 3, oy + rh - 3)
            // Floating platforms (one-way ledges) for verticality
            var py = oy + 6
            while py < oy + rh - 4 {
                let px = ox + r.range(3, rw - 11)
                let len = r.range(4, 8)
                for x in px..<(px + len) { set(x, py, .ledge) }
                if r.chance(0.35) { for x in (px + 1)..<(px + len - 1) { set(x, py + 1, .empty) } }
                py += r.range(3, 4)
            }
            // Pillars (wall-run surfaces)
            if r.chance(0.6) {
                let px = ox + r.range(6, rw - 8)
                for y in (oy + 2)...(oy + r.range(6, 10)) { set(px, y, .solid); set(px + 1, y, .solid) }
            }
            // Spike pit
            if i > 0 && r.chance(0.5 + Double(min(depth, 10)) * 0.03) {
                let sx = ox + r.range(5, rw - 10)
                for x in sx..<(sx + r.range(2, 4)) { set(x, oy + 2, .spike) }
            }
            // Populate
            let floorY = oy + 3
            if i == 0 { start = (ox + 4, floorY) }
            else if i == cells.count - 1 { portal = (ox + rw / 2, floorY) }
            else {
                let enemies = r.range(1, 2 + min(depth / 2, 3))
                for _ in 0..<enemies { spawns.append(Spawn(kind: .enemy, x: ox + r.range(4, rw - 5), y: oy + r.range(3, rh - 5))) }
                if r.chance(0.45) { spawns.append(Spawn(kind: .wanderer, x: ox + r.range(4, rw - 5), y: floorY)) }
                if r.chance(0.25) { spawns.append(Spawn(kind: .shrine, x: ox + r.range(4, rw - 5), y: floorY)) }
                if r.chance(0.4) { spawns.append(Spawn(kind: .chest, x: ox + r.range(4, rw - 5), y: floorY)) }
            }
        }
        // Connect consecutive rooms with doorways/shafts
        for i in 1..<cells.count {
            let a = cells[i - 1], b = cells[i]
            let ax = a.0 * rw + rw / 2, ay = a.1 * rh + 3
            let bx = b.0 * rw + rw / 2, by = b.1 * rh + 3
            if a.1 == b.1 {
                carve(min(ax, bx), ay, max(ax, bx), ay + 4)
            } else {
                let x = ax
                carve(x - 2, min(ay, by), x + 2, max(ay, by) + 3)
                // Ledges up the shaft so it's climbable (jump ~4 tiles)
                var y = min(ay, by) + 3
                var side = 0
                while y < max(ay, by) + 2 {
                    let sx = side == 0 ? x - 2 : x + 1
                    set(sx, y, .ledge); set(sx + 1, y, .ledge)
                    side ^= 1; y += 3
                }
                carve(min(ax, bx) - 2, by, max(ax, bx) + 2, by + 4)
            }
        }
        // Make sure spawn spots are not inside solids
        spawns = spawns.filter { at($0.x, $0.y) == .empty }
    }

    @inline(__always) func at(_ x: Int, _ y: Int) -> Tile {
        guard x >= 0, y >= 0, x < w, y < h else { return .solid }
        return g[y * w + x]
    }
    func set(_ x: Int, _ y: Int, _ t: Tile) { if x > 0, y > 0, x < w - 1, y < h - 1 { g[y * w + x] = t } }
    func solidAt(_ p: CGPoint) -> Bool { at(Int(p.x / T), Int(p.y / T)) == .solid }

    /// Bakes the tile map into lit, normal-mapped chunk textures (PoP2-style palace masonry with
    /// ambient occlusion, floor lips, ceiling shadows) plus torch positions. ~60 sprites total.
    func buildNode(theme: Theme, lights: [CGPoint] = []) -> SKNode {
        let root = SKNode()
        let chunk = 16, px = Int(T), cpx = chunk * px
        let stoneImg = Art.stone(theme.rock, variant: 1).cgImage()
        let backImg = Art.backWall(theme.rock).cgImage()
        func isSolid(_ x: Int, _ y: Int) -> Bool { at(x, y) == .solid }
        // Chunks are independent: bake them in parallel on all cores (pure CoreGraphics, no SpriteKit).
        var jobs: [(Int, Int)] = []
        for cy in stride(from: 0, to: h, by: chunk) { for cx in stride(from: 0, to: w, by: chunk) { jobs.append((cx, cy)) } }
        var results = [CGImage?](repeating: nil, count: jobs.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: jobs.count) { ji in
                let (cx, cy) = jobs[ji]
                var r = RNG(UInt64(cx * 7919 + cy * 104729 + w))
                let ctx = CGContext(data: nil, width: cpx, height: cpx, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                // 1. Back wall everywhere (tiled, world-aligned)
                for ty in stride(from: 0, to: cpx, by: 256) { for tx in stride(from: 0, to: cpx, by: 256) {
                    ctx.draw(backImg, in: CGRect(x: tx, y: ty, width: 256, height: 256)) } }
                // 2. Ambient occlusion on the back wall next to solids
                for ly in 0..<chunk { for lx in 0..<chunk {
                    let x = cx + lx, y = cy + ly
                    guard x < w, y < h, !isSolid(x, y) else { continue }
                    let rx = CGFloat(lx * px), ry = CGFloat(ly * px), s = CGFloat(px)
                    if isSolid(x, y + 1) { shade(ctx, CGRect(x: rx, y: ry, width: s, height: s), from: .top, a: 0.6) }
                    if isSolid(x, y - 1) { shade(ctx, CGRect(x: rx, y: ry, width: s, height: s * 0.5), from: .bottom, a: 0.35) }
                    if isSolid(x - 1, y) { shade(ctx, CGRect(x: rx, y: ry, width: s * 0.7, height: s), from: .left, a: 0.5) }
                    if isSolid(x + 1, y) { shade(ctx, CGRect(x: rx + s * 0.3, y: ry, width: s * 0.7, height: s), from: .right, a: 0.5) }
                } }
                // 3. Masonry for solid tiles (clip to the union of solid rects, draw tiled stone aligned to WORLD coords)
                ctx.saveGState()
                var any = false
                for ly in 0..<chunk { for lx in 0..<chunk where cx + lx < w && cy + ly < h && isSolid(cx + lx, cy + ly) {
                    ctx.addRect(CGRect(x: lx * px, y: ly * px, width: px, height: px)); any = true } }
                if any {
                    ctx.clip()
                    let ox = -CGFloat((cx * px) % 128), oy = -CGFloat((cy * px) % 128)
                    for ty in stride(from: oy, to: CGFloat(cpx), by: 128) { for tx in stride(from: ox, to: CGFloat(cpx), by: 128) {
                        ctx.draw(stoneImg, in: CGRect(x: tx, y: ty, width: 128, height: 128)) } }
                }
                ctx.restoreGState()
                // 4. Per-tile dressing
                for ly in 0..<chunk { for lx in 0..<chunk {
                    let x = cx + lx, y = cy + ly
                    guard x < w, y < h else { continue }
                    let rx = CGFloat(lx * px), ry = CGFloat(ly * px), s = CGFloat(px)
                    switch at(x, y) {
                    case .solid:
                        let airAbove = !isSolid(x, y + 1), airBelow = !isSolid(x, y - 1)
                        // interior mass darkens with depth from air -> walls read as solid volume
                        var depth = 3
                        for d in 1...2 where !isSolid(x, y + d) || !isSolid(x, y - d) || !isSolid(x + d, y) || !isSolid(x - d, y) { depth = min(depth, d) }
                        if depth >= 2 { ctx.setFillColor(CGColor(gray: 0, alpha: depth == 2 ? 0.45 : 0.82)); ctx.fill(CGRect(x: rx, y: ry, width: s, height: s)) }
                        if airAbove {   // walkable floor: PoP-style lit slab top + bright edge + front-face shadow line
                            ctx.setFillColor(Art.rgba(theme.rock.blended(withFraction: 0.45, of: .white)!)); ctx.fill(CGRect(x: rx, y: ry + s - 8, width: s, height: 8))
                            ctx.setFillColor(CGColor(gray: 1, alpha: 0.55)); ctx.fill(CGRect(x: rx, y: ry + s - 2, width: s, height: 2))
                            ctx.setFillColor(CGColor(gray: 0, alpha: 0.5)); ctx.fill(CGRect(x: rx, y: ry + s - 11, width: s, height: 3))
                            if !isSolid(x - 1, y) || !isSolid(x + 1, y) {   // exposed corner: chipped bevel
                                ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
                                ctx.fill(CGRect(x: !isSolid(x - 1, y) ? rx : rx + s - 3, y: ry, width: 3, height: s - 8))
                            }
                            if r.chance(0.12) {  // rubble
                                ctx.setFillColor(Art.rgba(theme.rock.blended(withFraction: 0.2, of: .white)!))
                                ctx.fillEllipse(in: CGRect(x: rx + CGFloat(r.range(2, 20)), y: ry + s - 2, width: 6, height: 4))
                            }
                        }
                        if airBelow { ctx.setFillColor(CGColor(gray: 0, alpha: 0.45)); ctx.fill(CGRect(x: rx, y: ry, width: s, height: 5)) }
                    case .ledge:
                        // Chunky stone slab (PoP floor tile): lit top, carved front face, dark underside, cast shadow
                        let top = ry + s
                        let slabH: CGFloat = 16
                        ctx.saveGState()
                        ctx.clip(to: CGRect(x: rx, y: top - slabH, width: s, height: slabH))
                        ctx.draw(stoneImg, in: CGRect(x: rx - CGFloat((x * px) % 128), y: top - 128, width: 128, height: 128))
                        ctx.restoreGState()
                        ctx.setFillColor(Art.rgba(theme.rock.blended(withFraction: 0.5, of: .white)!)); ctx.fill(CGRect(x: rx, y: top - 5, width: s, height: 5))
                        ctx.setFillColor(CGColor(gray: 1, alpha: 0.6)); ctx.fill(CGRect(x: rx, y: top - 1.5, width: s, height: 1.5))
                        ctx.setFillColor(CGColor(gray: 0, alpha: 0.45)); ctx.fill(CGRect(x: rx, y: top - 7, width: s, height: 2))
                        ctx.setFillColor(CGColor(gray: 0, alpha: 0.7)); ctx.fill(CGRect(x: rx, y: top - slabH, width: s, height: 3))
                        if at(x - 1, y) != .ledge || at(x + 1, y) != .ledge {   // carved corbel bracket under slab ends
                            let left = at(x - 1, y) != .ledge
                            let bx = left ? rx + 2 : rx + s - 16
                            ctx.setFillColor(Art.rgba(theme.rock.blended(withFraction: 0.25, of: .black)!))
                            ctx.move(to: CGPoint(x: bx, y: top - slabH)); ctx.addLine(to: CGPoint(x: bx + 14, y: top - slabH))
                            ctx.addQuadCurve(to: CGPoint(x: left ? bx + 2 : bx + 12, y: top - slabH - 22), control: CGPoint(x: left ? bx + 14 : bx, y: top - slabH - 14))
                            ctx.closePath(); ctx.fillPath()
                            ctx.setFillColor(CGColor(gray: 0, alpha: 0.6)); ctx.fill(CGRect(x: left ? rx : rx + s - 3, y: top - slabH, width: 3, height: slabH))
                        }
                        shade(ctx, CGRect(x: rx, y: top - slabH - 30, width: s, height: 30), from: .top, a: 0.65)
                    case .spike:
                        for k in 0..<4 {
                            let sx = rx + CGFloat(k) * s / 4 + 1
                            let tip = CGPoint(x: sx + s / 8, y: ry + s * CGFloat(0.65 + 0.15 * Double(k % 2)))
                            ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
                            ctx.move(to: CGPoint(x: sx, y: ry)); ctx.addLine(to: tip); ctx.addLine(to: CGPoint(x: sx + s / 4 - 2, y: ry)); ctx.fillPath()
                            ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
                            ctx.move(to: CGPoint(x: sx + 1, y: ry)); ctx.addLine(to: tip); ctx.addLine(to: CGPoint(x: sx + 3, y: ry)); ctx.fillPath()
                            ctx.setFillColor(CGColor(red: 0.5, green: 0.05, blue: 0.05, alpha: 0.7)); ctx.fillEllipse(in: CGRect(x: tip.x - 1.5, y: tip.y - 5, width: 3, height: 4))
                        }
                    case .empty: break
                    }
                } }
                // 5. Baked lighting pass: darkness everywhere, warm radial pools around every torch (world-space,
                // so pools cross chunk borders seamlessly). Multiply onto the albedo.
                let lightCtx = CGContext(data: nil, width: cpx, height: cpx, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                lightCtx.setFillColor(Art.rgba(theme.mist.blended(withFraction: 0.72, of: .black)!)); lightCtx.fill(CGRect(x: 0, y: 0, width: cpx, height: cpx))
                lightCtx.setBlendMode(.plusLighter)
                let ox = CGFloat(cx * px), oy = CGFloat(cy * px)
                let warm = CGGradient(colorsSpace: nil, colors: [CGColor(red: 1, green: 0.78, blue: 0.5, alpha: 0.95), CGColor(red: 0.85, green: 0.45, blue: 0.2, alpha: 0.45), CGColor(red: 0.5, green: 0.2, blue: 0.1, alpha: 0)] as CFArray, locations: [0, 0.35, 1])!
                let radius: CGFloat = 300
                for l in lights where l.x > ox - radius && l.x < ox + CGFloat(cpx) + radius && l.y > oy - radius && l.y < oy + CGFloat(cpx) + radius {
                    let c = CGPoint(x: l.x - ox, y: l.y - oy)
                    lightCtx.drawRadialGradient(warm, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
                }
                let lightImg = lightCtx.makeImage()!
                ctx.setBlendMode(.multiply); ctx.draw(lightImg, in: CGRect(x: 0, y: 0, width: cpx, height: cpx))
                // A touch of additive warmth on lit stone so highlights glow rather than just un-darken
                ctx.setBlendMode(.screen); ctx.setAlpha(0.18); ctx.draw(lightImg, in: CGRect(x: 0, y: 0, width: cpx, height: cpx))
                ctx.setBlendMode(.normal); ctx.setAlpha(1)
                let img = ctx.makeImage()!
                lock.lock(); results[ji] = img; lock.unlock()
        }
        for (ji, res) in results.enumerated() {
            guard let img = res else { continue }
            let (cx, cy) = jobs[ji]
            let n = SKSpriteNode(texture: SKTexture(cgImage: img))
            n.lightingBitMask = 0   // lighting is baked: seamless across chunks, zero per-pixel cost
            n.anchorPoint = .zero; n.position = CGPoint(x: CGFloat(cx) * T, y: CGFloat(cy) * T); n.zPosition = -10
            root.addChild(n)
        }
        return root
    }

    enum Edge { case top, bottom, left, right }
    private func shade(_ c: CGContext, _ rect: CGRect, from e: Edge, a: CGFloat) {
        let g = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 0, alpha: a), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 1])!
        c.saveGState(); c.clip(to: rect)
        switch e {
        case .top: c.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
        case .bottom: c.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        case .left: c.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
        case .right: c.drawLinearGradient(g, start: CGPoint(x: rect.maxX, y: 0), end: CGPoint(x: rect.minX, y: 0), options: [])
        }
        c.restoreGState()
    }

    /// Wall-mounted torch spots: back-wall tiles two above a floor, spaced out.
    func torchSpots() -> [CGPoint] {
        var out: [CGPoint] = [], lastX = -100, lastY = -1
        for y in 2..<(h - 2) {
            lastX = -100
            for x in 1..<(w - 1) where at(x, y) == .empty && at(x, y - 1) == .empty && at(x, y - 2) == .solid && at(x, y + 1) == .empty {
                if x - lastX >= 11 || y != lastY { if x - lastX >= 11 { out.append(CGPoint(x: (CGFloat(x) + 0.5) * T, y: (CGFloat(y) + 0.6) * T)); lastX = x; lastY = y } }
            }
        }
        return out
    }
}
