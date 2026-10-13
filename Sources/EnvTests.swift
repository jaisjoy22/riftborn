import SpriteKit

// MARK: - v3 phase 6 selftest: small environmental gameplay set (named failures; isolated scenes)

/// Props fixture dressing (tiles; arena floor row is v3Arena.y0): a gated 2-tile alcove at the left wall with
/// its plate to the right of the start, two open-floor potions, pillars and a skeleton. The portal route
/// (rightwards) never passes the gate.
let v3PropsGate = (column: 6, top: 8)
let v3PropsPlateX = 7
func addV3PropsDecor(_ w: World) {
    let fy = v3Arena.y0
    let pt = { (x: Int) in CGPoint(x: (CGFloat(x) + 0.5) * T, y: CGFloat(fy) * T) }
    for y in v3PropsGate.top...v3Arena.y1 { w.set(v3PropsGate.column, y, .solid) }   // lintel/wall above the gate
    w.decor = [
        WorldProp(kind: .gate, position: pt(v3PropsGate.column), link: 0),
        WorldProp(kind: .plate, position: pt(v3PropsPlateX), link: 0),
        WorldProp(kind: .healPotion, position: pt(v3Arena.x0)),        // reward behind the gate
        WorldProp(kind: .healPotion, position: pt(22)),
        WorldProp(kind: .growthPotion, position: pt(26)),
        WorldProp(kind: .healPotion, position: pt(40)),
        WorldProp(kind: .pillar, position: pt(30)),
        WorldProp(kind: .pillar, position: pt(36)),
        WorldProp(kind: .skeleton, position: pt(33)),
    ]
    w.closedGateRects = [0: World.gateRect(column: v3PropsGate.column, floor: fy, tiles: v3PropsGate.top - fy)]
}

/// Tile flood fill from start (4-connected over non-solid tiles), with tiles overlapping closed gates blocked.
private func reachable(_ w: World, from s: (x: Int, y: Int), to t: (x: Int, y: Int), gatesClosed: Bool) -> Bool {
    var seen = [Bool](repeating: false, count: w.w * w.h), stack = [s.y * w.w + s.x]
    func blocked(_ x: Int, _ y: Int) -> Bool {
        if w.at(x, y) == .solid { return true }
        return gatesClosed && w.gateBlocks(CGRect(x: CGFloat(x) * T + 1, y: CGFloat(y) * T + 1, width: T - 2, height: T - 2))
    }
    while let i = stack.popLast() {
        if seen[i] { continue }; seen[i] = true
        let x = i % w.w, y = i / w.w
        if x == t.x && y == t.y { return true }
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !blocked(x + dx, y + dy) && !seen[(y + dy) * w.w + x + dx] {
            stack.append((y + dy) * w.w + x + dx)
        }
    }
    return false
}

func runV3EnvTests(_ failures: inout [String]) {
    let inp = Input.shared
    let wasSuppressed = inp.suppressHardware
    inp.suppressHardware = true
    defer { inp.suppressHardware = wasSuppressed; resetTestInput(inp) }

    // 1. Generated decor: deterministic, capped, never on solids/spawns, never cutting the main route.
    var pairs = 0, heals = 0, growths = 0, pillars = 0, worlds = 0
    for seed in UInt64(1)...24 { for depth in 1...10 {
        let a = World(seed: seed, depth: depth), b = World(seed: seed, depth: depth)
        worlds += 1
        let tag = "v3 env seed \(seed) depth \(depth)"
        if a.g != b.g || a.decor != b.decor || a.closedGateRects != b.closedGateRects { failures.append("\(tag): decor not deterministic"); continue }
        let c = World(seed: seed, depth: depth); c.placeDecor(seed: seed &+ 99)
        if c.g != a.g || c.spawns.count != a.spawns.count { failures.append("\(tag): decor stream perturbed layout") }
        func n(_ k: WorldProp.Kind) -> Int { a.decor.filter { $0.kind == k }.count }
        let rooms = a.rooms.count
        if n(.pillar) > 2 * rooms || n(.skeleton) > rooms { failures.append("\(tag): dressing exceeds per-room caps") }
        for room in a.rooms {
            let ox = CGFloat(room.x * World.roomW) * T, oy = CGFloat(room.y * World.roomH) * T
            let inRoom = a.decor.filter { $0.position.x >= ox && $0.position.x < ox + CGFloat(World.roomW) * T && $0.position.y >= oy && $0.position.y < oy + CGFloat(World.roomH) * T }
            if inRoom.filter({ $0.kind == .pillar }).count > 2 || inRoom.filter({ $0.kind == .skeleton }).count > 1 { failures.append("\(tag): room dressing cap exceeded") }
        }
        if n(.healPotion) > 3 { failures.append("\(tag): \(n(.healPotion)) heal potions (cap 3)") }
        if n(.growthPotion) > 1 { failures.append("\(tag): \(n(.growthPotion)) growth potions (cap 1)") }
        if n(.gate) > 1 || n(.gate) != n(.plate) || a.closedGateRects.count != n(.gate) { failures.append("\(tag): plate/gate pairing broken") }
        if n(.exitFrame) != 1 { failures.append("\(tag): expected one exit frame") }
        heals += n(.healPotion); growths += n(.growthPotion); pillars += n(.pillar); pairs += n(.gate)
        for d in a.decor {
            let tx = Int(d.position.x / T), ty = Int(d.position.y / T)
            if a.at(tx, ty) == .solid { failures.append("\(tag): \(d.kind) inside solid"); break }
            if d.kind == .healPotion || d.kind == .growthPotion || d.kind == .plate {
                if a.spawns.contains(where: { $0.x == tx && $0.y == ty }) { failures.append("\(tag): \(d.kind) consumed a spawn"); break }
                if a.at(tx, ty - 1) != .solid { failures.append("\(tag): \(d.kind) not on floor"); break }
            }
            if d.kind == .pillar && !a.bodyFits(CGRect(x: d.position.x - 16, y: d.position.y, width: 32, height: 150)) { failures.append("\(tag): pillar claims blocked space"); break }
        }
        for (id, r) in a.closedGateRects {
            let g = a.decor.first { $0.kind == .gate && $0.link == id }
            let p = a.decor.first { $0.kind == .plate && $0.link == id }
            if g == nil || p == nil { failures.append("\(tag): gate \(id) missing gate/plate descriptor") }
            if a.closedGateRects.count > 0, !World(seed: 0, depth: 1).bodyFits(.zero) || !{ let t = a.closedGateRects; a.closedGateRects = [:]; defer { a.closedGateRects = t }; return a.bodyFits(r) }() { failures.append("\(tag): gate \(id) overlaps solid tiles") }
            if a.gateBlocks(CGRect(x: CGFloat(a.start.x) * T, y: CGFloat(a.start.y) * T, width: T, height: T)) { failures.append("\(tag): gate on start") }
            if let p = p, a.gateBlocks(CGRect(x: p.position.x - 14, y: p.position.y, width: 28, height: 6)) { failures.append("\(tag): plate under its gate") }
        }
        if !a.closedGateRects.isEmpty {
            let open = reachable(a, from: a.start, to: a.portal, gatesClosed: false)
            let closed = reachable(a, from: a.start, to: a.portal, gatesClosed: true)
            if open && !closed { failures.append("\(tag): closed gate blocks the main route") }
        }
    } }

    // 2. Props fixture: live props built, baked dressing not duplicated as nodes, exit frame wraps the portal.
    let s = GameScene(size: CGSize(width: 1440, height: 900))
    prepareV3Fixture(s, .props); resetTestInput(inp)
    advanceTest(s, frames: 30, acts: [])
    let p = s.player!
    let live = s.worldProps.map { $0.descriptor.kind }
    if live.contains(.pillar) || live.contains(.skeleton) { failures.append("v3 env: baked dressing built as live nodes") }
    if live.filter({ $0 == .healPotion }).count != 3 || !live.contains(.growthPotion) || !live.contains(.plate) || !live.contains(.gate) {
        failures.append("v3 env: props fixture live set wrong \(live)")
    }
    if s.portalNode.childNode(withName: "exitFrame") == nil { failures.append("v3 env: exit frame does not wrap the portal") }
    if s.worldProps.contains(where: { $0.node.parent == nil }) { failures.append("v3 env: live prop node not attached") }
    for d in s.world.decor where d.kind == .pillar {
        if !s.world.bodyFits(CGRect(x: d.position.x - p.size.width / 2, y: d.position.y, width: p.size.width, height: p.size.height)) { failures.append("v3 env: pillar has collision") }
    }

    func standAt(_ x: CGFloat) { p.pos = CGPoint(x: x, y: CGFloat(v3Arena.y0) * T); p.vel = .zero; p.node.position = p.pos }
    func idx(_ k: WorldProp.Kind, _ x: CGFloat? = nil) -> Int? { s.worldProps.firstIndex { $0.descriptor.kind == k && (x == nil || $0.descriptor.position.x == x!) } }
    let healX = (CGFloat(22) + 0.5) * T, heal2X = (CGFloat(40) + 0.5) * T, growX = (CGFloat(26) + 0.5) * T

    // 3. Red potion: full HP leaves it; missing HP heals 25 once, clamped to maxHP.
    do {
        p.hp = p.maxHP; standAt(healX); advanceTest(s, frames: 1, acts: [])
        if let i = idx(.healPotion, healX), s.worldProps[i].used { failures.append("v3 env: heal consumed at full HP") }
        p.hp = 50; standAt(healX); advanceTest(s, frames: 1, acts: [])
        if abs(p.hp - 75) > 0.001 { failures.append("v3 env: heal gave \(p.hp - 50), expected 25") }
        if let i = idx(.healPotion, healX), !s.worldProps[i].used { failures.append("v3 env: heal not marked used") }
        p.hp = 50; standAt(healX); advanceTest(s, frames: 3, acts: [])
        if abs(p.hp - 50) > 0.001 { failures.append("v3 env: heal fired twice") }
        p.hp = p.maxHP - 10; standAt(heal2X); advanceTest(s, frames: 1, acts: [])
        if abs(p.hp - p.maxHP) > 0.001 { failures.append("v3 env: heal not clamped to maxHP (\(p.hp)/\(p.maxHP))") }
    }
    // 4. Green potion: +5 maxHP on Chronicle and player immediately, heal 5, once.
    do {
        let m0 = s.chron.maxHP
        p.hp = 60; standAt(growX); advanceTest(s, frames: 1, acts: [])
        if s.chron.maxHP != m0 + 5 || p.maxHP != CGFloat(s.chron.maxHP) { failures.append("v3 env: growth maxHP \(s.chron.maxHP)/\(p.maxHP), expected \(m0 + 5)") }
        if abs(p.hp - 65) > 0.001 { failures.append("v3 env: growth healed \(p.hp - 60), expected 5") }
        standAt(growX); advanceTest(s, frames: 3, acts: [])
        if s.chron.maxHP != m0 + 5 { failures.append("v3 env: growth fired twice") }
        if s.persistCount != 0 { failures.append("v3 env: test session persisted a pickup") }
    }
    // 5. Gate: closed gate blocks; plate opens only its linked gate; 0.08 s response; collision clears by 0.35 s.
    do {
        let gr = s.world.closedGateRects[0] ?? .zero
        let decoy = CGRect(x: 40 * T, y: 15 * T, width: 20, height: 40)
        s.world.closedGateRects[7] = decoy
        let pi = idx(.plate)
        if let pi = pi { s.worldProps[pi].used = true }        // walk into the gate across a disarmed plate
        standAt(gr.maxX + 20); advanceTest(s, frames: 60, acts: [.left])
        if let pi = pi { s.worldProps[pi].used = false }
        if p.rect.minX < gr.maxX - 0.5 { failures.append("v3 env: closed gate did not block (\(p.rect.minX) < \(gr.maxX))") }
        if s.gateOpenings != 0 { failures.append("v3 env: gate opened without plate") }
        standAt((CGFloat(v3PropsPlateX) + 0.5) * T); advanceTest(s, frames: 1, acts: [])
        if s.gateOpenings != 1 { failures.append("v3 env: plate did not open gate (\(s.gateOpenings))") }
        if s.world.closedGateRects[7] != decoy { failures.append("v3 env: plate opened an unlinked gate") }
        advanceTest(s, frames: 5, acts: [])
        if let gi = idx(.gate), let bars = s.worldProps[gi].node.childNode(withName: "bars"), bars.yScale > 0.999 { failures.append("v3 env: gate showed no response within 0.08 s") }
        advanceTest(s, frames: 17, acts: [])
        if s.world.closedGateRects[0] != nil { failures.append("v3 env: gate collision persisted past 0.35 s") }
        standAt((CGFloat(v3PropsPlateX) + 0.5) * T); advanceTest(s, frames: 2, acts: [])
        if s.gateOpenings != 1 { failures.append("v3 env: plate retriggered") }
        p.hp = 40; standAt(gr.maxX + 40); advanceTest(s, frames: 90, acts: [.left])
        if p.rect.maxX > gr.minX { failures.append("v3 env: opened gate still blocks (\(p.pos.x))") }
        if p.hp <= 40 { failures.append("v3 env: alcove potion behind opened gate not reachable") }
        s.world.closedGateRects[7] = nil
    }
    // 6. Main route works with the gate closed (fresh fixture: walk right to the portal).
    do {
        let s2 = GameScene(size: CGSize(width: 1440, height: 900))
        prepareV3Fixture(s2, .props); resetTestInput(inp)
        advanceTest(s2, frames: 20, acts: [])
        var reached = false
        for _ in 0..<600 where !reached { advanceTest(s2, frames: 1, acts: [.right]); reached = s2.mode == .portal }
        if !reached { failures.append("v3 env: main route to portal blocked with gate closed (player \(s2.player.pos))") }
        if s2.world.closedGateRects[0] == nil { failures.append("v3 env: gate opened on the main route") }
    }
    // 7. Rebuild clears old props/gates and rebuilds fresh live state.
    do {
        let oldNodes = s.worldProps.map { $0.node }
        s.buildDepth()
        if oldNodes.contains(where: { $0.parent != nil && $0.scene != nil }) { failures.append("v3 env: rebuild left stale prop nodes") }
        if s.worldProps.contains(where: { $0.used }) || s.world.closedGateRects[0] == nil { failures.append("v3 env: rebuild carried used/opened state") }
        if s.world.closedGateRects.count != s.world.decor.filter({ $0.kind == .gate }).count { failures.append("v3 env: rebuild gate rects mismatch") }
        if s.worldProps.count != s.world.decor.filter({ $0.kind != .pillar && $0.kind != .skeleton }).count { failures.append("v3 env: rebuild live prop count mismatch") }
    }
    print("  v3 env props     : \(worlds) worlds, gate pairs \(pairs), heals \(heals), growth \(growths), pillars \(pillars)")
}
