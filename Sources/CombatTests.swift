import SpriteKit

// MARK: - v3 phase 4 selftest: directional, committed combat (named failures; isolated scenes/inputs)

/// Fresh combat fixture with a single passive Warden placed `dx` in front of the settled player.
private func combatDuelScene(dx: CGFloat = 40) -> (GameScene, Being) {
    let inp = Input.shared
    let s = GameScene(size: CGSize(width: 1440, height: 900))
    prepareV3Fixture(s, .combat)
    s.beings.forEach { $0.node.removeFromParent() }; s.beings.removeAll()
    resetTestInput(inp)
    advanceTest(s, frames: 30, acts: [])
    var soul = Soul(id: 9001, name: "Test Warden", faction: .wardens, motive: .duty, backstory: "")
    soul.level = 2
    let p = s.player!
    let foe = Being(soul: soul, pos: CGPoint(x: p.pos.x + dx, y: p.pos.y), role: .hostile)
    foe.maxHP = 100_000; foe.hp = foe.maxHP; foe.facing = -1
    s.beings.append(foe); s.worldNode.addChild(foe.node)
    p.facing = 1; p.energy = 100
    return (s, foe)
}

/// Keep the foe in place and unable to strike (refrac gates every PoP strike roll).
private func pin(_ foe: Being, at x: CGFloat, block: Bool) {
    foe.pos.x = x; foe.vel = .zero; foe.refrac = 10; foe.facing = -1; foe.phase = .none
    if block { foe.blockT = 10 }
}

private func standalonePlayer() -> (Player, World, Input) {
    let w = World(seed: 5, depth: 1)
    let pl = Player(pos: CGPoint(x: (CGFloat(w.start.x) + 0.5) * T, y: CGFloat(w.start.y) * T))
    let i = Input(); i.suppressHardware = true
    for _ in 0..<30 { i.synthetic = []; i.poll(); pl.update(1.0 / 60, w, i) }
    pl.energy = 100
    return (pl, w, i)
}

func runV3CombatTests(_ failures: inout [String]) {
    let inp = Input.shared
    let wasSuppressed = inp.suppressHardware
    inp.suppressHardware = true
    defer { inp.suppressHardware = wasSuppressed; resetTestInput(inp) }
    var notes: [String] = []

    // Spec table contract
    let th = AttackSpec.thrust, hv = AttackSpec.heavy
    if !(th.windup == 0.09 && th.active == 0.07 && th.recovery == 0.22 && th.lunge == 260 && th.reach == 78 && th.damage == 0.90
         && th.knock == 180 && th.hitStop == 0.045 && th.shake == 4) { failures.append("v3 combat: thrust spec values wrong") }
    if !(hv.windup == 0.17 && hv.active == 0.10 && hv.recovery == 0.32 && hv.damage == 2.4 && hv.reach == 76
         && hv.lunge == 360 && hv.knock == 460 && hv.hitStop == 0.085 && hv.shake == 9) { failures.append("v3 combat: heavy spec values wrong") }
    if !hv.breaksGuard || AttackSpec.light1.breaksGuard || AttackSpec.light2.breaksGuard || th.breaksGuard { failures.append("v3 combat: breaksGuard flags wrong") }
    if !(th.windup < th.recovery) { failures.append("v3 combat: thrust violates anticipation<recovery") }

    // Every kind exposes a swing only during .active; thrust/overhead boxes; up+attack does not jump; down+attack keeps body size.
    for (acts, kind) in [([Act.attack], AttackKind.slash), ([.down, .attack], .thrust), ([.up, .jump, .attack], .overhead)] {
        let (pl, w, i) = standalonePlayer()
        let h0 = pl.rect.height, y0 = pl.pos.y
        var seen: [Phase] = [], swingOutside = false, sawSwing = false, maxDy: CGFloat = 0, box: CGRect? = nil
        for f in 0..<70 {
            i.synthetic = f == 1 ? Set(acts) : []
            i.poll(); pl.update(1.0 / 60, w, i)
            if seen.last != pl.phase { seen.append(pl.phase) }
            if let s = pl.swing { sawSwing = true; box = s; if pl.phase != .active { swingOutside = true } }
            else if pl.phase == .active { swingOutside = true }
            maxDy = max(maxDy, pl.pos.y - y0)
            if pl.rect.height != h0 { failures.append("v3 combat \(kind): attacking body changed height"); break }
        }
        if seen != [.none, .windup, .active, .recovery, .none] { failures.append("v3 combat \(kind): phases wrong \(seen)") }
        if pl.attackKind != kind { failures.append("v3 combat: modifier selected \(pl.attackKind), expected \(kind)") }
        if !sawSwing || swingOutside { failures.append("v3 combat \(kind): swing not exclusive to .active") }
        if maxDy > 0.5 { failures.append("v3 combat \(kind): attack press also jumped (rose \(maxDy))") }
        if let b = box {
            switch kind {
            case .thrust: if b.height != 22 || abs(b.minY - (pl.pos.y + 22)) > 0.5 || b.width != 78 { failures.append("v3 combat: thrust box wrong \(b)") }
            case .overhead: if b.height != 66 || b.width != 76 { failures.append("v3 combat: overhead box wrong \(b)") }
            case .slash: if b.height != 52 { failures.append("v3 combat: slash box changed \(b)") }
            }
        }
    }
    // Thrust reach mirrors with facing.
    do {
        let (pl, w, i) = standalonePlayer()
        func thrustBox(_ facing: CGFloat) -> CGRect? {
            pl.facing = facing; pl.vel = .zero
            var out: CGRect? = nil
            for f in 0..<40 {
                i.synthetic = f == 0 ? [.down, .attack] : []
                i.poll(); pl.update(1.0 / 60, w, i)
                if out == nil, let s = pl.swing { out = s }
            }
            return out
        }
        if let r = thrustBox(1), let l = thrustBox(-1) {
            let pr = r.maxX - pl.pos.x, pL = pl.pos.x - l.minX
            // positions drift by lunge, so compare reach relative to the body at the active moment via widths/offsets
            if abs(r.width - l.width) > 0.01 || abs(r.height - l.height) > 0.01 || pr <= 0 || pL <= 0 { failures.append("v3 combat: thrust not mirrored (\(r) vs \(l))") }
        } else { failures.append("v3 combat: thrust produced no box in one facing") }
    }

    // Low-energy overhead falls back to light1; energy never negative. Exact cost path too.
    do {
        let (pl, w, i) = standalonePlayer()
        pl.energy = 5
        i.synthetic = [.up, .attack]; i.poll(); pl.update(1.0 / 60, w, i)
        if pl.attackKind != .slash || pl.spec.damage != AttackSpec.light1.damage { failures.append("v3 combat: low-energy overhead did not fall back to light1") }
        if pl.energy < 0 { failures.append("v3 combat: energy went negative") }
        let (p2, w2, i2) = standalonePlayer()
        p2.energy = AttackSpec.overheadCost
        i2.synthetic = [.up, .attack]; i2.poll(); p2.update(1.0 / 60, w2, i2)
        if p2.attackKind != .overhead || p2.energy < 0 || p2.energy > 1 { failures.append("v3 combat: overhead energy cost wrong (\(p2.attackKind), \(p2.energy))") }
    }

    // Modifier captured at press time: down+attack pressed during a slash, down released before the chain starts.
    do {
        let (pl, w, i) = standalonePlayer()
        i.synthetic = [.attack]; i.poll(); pl.update(1.0 / 60, w, i)
        var f = 0
        while pl.phase != .active && f < 30 { i.synthetic = []; i.poll(); pl.update(1.0 / 60, w, i); f += 1 }
        let firstId = pl.swingId
        i.synthetic = [.down, .attack]; i.poll(); pl.update(1.0 / 60, w, i)
        f = 0
        while pl.swingId == firstId && f < 40 { i.synthetic = []; i.poll(); pl.update(1.0 / 60, w, i); f += 1 }
        if pl.swingId == firstId || pl.attackKind != .thrust { failures.append("v3 combat: buffered modifier not captured at press (\(pl.attackKind))") }
        // Chaining is not allowed before 0.09 s of recovery.
        let (p3, w3, i3) = standalonePlayer()
        i3.synthetic = [.attack]; i3.poll(); p3.update(1.0 / 60, w3, i3)
        var earliest = -1.0
        for _ in 0..<40 {
            i3.synthetic = i3.held(.attack) ? [] : [.attack]; i3.poll()
            let before = p3.swingId, wasRec = p3.phase == .recovery, recT = p3.spec.recovery - p3.phaseT
            p3.update(1.0 / 60, w3, i3)
            if p3.swingId != before && wasRec && earliest < 0 { earliest = recT + 1.0 / 60 }
        }
        if earliest >= 0 && earliest < 0.09 - 1.0 / 60 - 1e-6 { failures.append("v3 combat: light chained before 0.09 s of recovery (\(earliest))") }
    }

    // Press during scene hit-stop is captured with its modifier and fires once play resumes.
    do {
        let (s, foe) = combatDuelScene(dx: 300)
        _ = foe
        s.hitStop = 0.2
        advanceTest(s, frames: 1, acts: [.down, .attack])
        let p = s.player!
        if !(p.bufferedAttack > 0 && p.bufferedKind == .thrust) { failures.append("v3 combat: attack press during hit-stop not captured") }
        var f = 0
        while p.phase == .none && f < 30 { advanceTest(s, frames: 1, acts: []); f += 1 }
        if p.attackKind != .thrust || p.phase == .none { failures.append("v3 combat: hit-stop buffered thrust did not start (\(p.attackKind) \(p.phase))") }
        // Modal change discards buffering.
        let (s2, _) = combatDuelScene(dx: 300)
        s2.hitStop = 0.2
        advanceTest(s2, frames: 1, acts: [.attack])
        s2.mode = .paused
        advanceTest(s2, frames: 1, acts: [])
        s2.mode = .play; s2.hitStop = 0
        advanceTest(s2, frames: 3, acts: [])
        if s2.player.phase != .none || s2.player.bufferedAttack > 0 { failures.append("v3 combat: modal change did not discard attack buffer") }
    }

    // One outcome per target per swingId; ordinary guard recoils and recoilLock blocks dash/jump/chain.
    do {
        let (s, foe) = combatDuelScene()
        let p = s.player!, fx = foe.pos.x
        pin(foe, at: fx, block: true)
        advanceTest(s, frames: 1, acts: [.attack])
        var outcomes = 0, sawLock = false, bypass = false
        for _ in 0..<60 {
            pin(foe, at: fx, block: true)
            let c0 = s.combat.hits + s.combat.blockedByFoe + s.combat.guardBreaks
            let id0 = p.swingId
            // Mash everything during the lock: none of it may cancel the recoil.
            let acts: Set<Act> = p.recoilLock > 0 ? (s.stats.frames % 2 == 0 ? [.dash, .jump, .attack] : []) : []
            advanceTest(s, frames: 1, acts: acts)
            outcomes += s.combat.hits + s.combat.blockedByFoe + s.combat.guardBreaks - c0
            if p.recoilLock > 0 { sawLock = true; if p.swingId != id0 || p.dashTimer > 0 || p.vel.dy > 100 { bypass = true } }
        }
        if s.combat.blockedByFoe != 1 { failures.append("v3 combat: ordinary guard did not recoil once (\(s.combat.blockedByFoe))") }
        if outcomes != 1 { failures.append("v3 combat: \(outcomes) outcomes for one swingId") }
        if !sawLock { failures.append("v3 combat: recoil did not set recoilLock") }
        if bypass { failures.append("v3 combat: recoilLock bypassed by dash/jump/chain") }
        if s.combat.guardBreaks != 0 { failures.append("v3 combat: light attack broke guard") }
    }

    // Guard break: overhead vs block clears block, counts once, reduced damage, not a parry.
    do {
        let (s, foe) = combatDuelScene()
        let p = s.player!, fx = foe.pos.x
        let parries0 = s.combat.parries
        pin(foe, at: fx, block: true)
        let hp0 = foe.hp
        advanceTest(s, frames: 1, acts: [.up, .attack])
        if p.attackKind != .overhead { failures.append("v3 combat: up+attack did not start overhead") }
        var broke = false, blockAfter = -1.0, hpAfter = hp0, stunAfter = 0.0
        for _ in 0..<60 {
            if !broke { pin(foe, at: fx, block: true) }
            let g0 = s.combat.guardBreaks
            advanceTest(s, frames: 1, acts: [])
            if s.combat.guardBreaks > g0 && !broke { broke = true; blockAfter = foe.blockT; hpAfter = foe.hp; stunAfter = foe.stun }
        }
        let expected = CGFloat(s.chron.power) * AttackSpec.heavy.damage * 0.65
        if s.combat.guardBreaks != 1 { failures.append("v3 combat: guardBreaks \(s.combat.guardBreaks), expected 1") }
        if blockAfter != 0 { failures.append("v3 combat: guard break left block up (\(blockAfter))") }
        if abs((hp0 - hpAfter) - expected) > 0.01 { failures.append("v3 combat: guard-break damage \(hp0 - hpAfter), expected \(expected)") }
        if !(stunAfter > 0.4 && stunAfter <= 0.45) { failures.append("v3 combat: guard break stagger \(stunAfter)") }
        if s.combat.parries != parries0 { failures.append("v3 combat: guard break counted as parry") }
        if s.combat.blockedByFoe != 0 { failures.append("v3 combat: overhead was treated as ordinary block") }
        notes.append("guard break dmg \(String(format: "%.1f", hp0 - hpAfter))")
    }

    // Corpse pass: animation advances outside living AI; reward and consequences fire once; removed ~1.9 s.
    do {
        let (s, foe) = combatDuelScene()
        let kills0 = s.stats.kills
        s.kill(foe)
        let xp1 = s.chron.xp, sh1 = s.chron.shards, kills1 = s.stats.kills
        s.kill(foe); s.damage(foe, 5, by: nil, dir: 1, spec: nil)
        if kills1 != kills0 + 1 || s.stats.kills != kills1 || s.chron.xp != xp1 || s.chron.shards != sh1 { failures.append("v3 combat: kill consequences applied more than once") }
        advanceTest(s, frames: 30, acts: [])
        if foe.deathT <= 0 { failures.append("v3 combat: corpse animation did not advance") }
        if foe.phase != .none { failures.append("v3 combat: dead being ran attack logic") }
        let rp = foe.rig.pose
        if abs(rp.torso - Pose.dead.torso) > 0.6 { failures.append("v3 combat: corpse did not collapse toward .dead (torso \(rp.torso))") }
        advanceTest(s, frames: 150, acts: [])
        if s.beings.contains(where: { $0 === foe }) || foe.node.parent != nil { failures.append("v3 combat: corpse not removed by ~1.9 s") }
        // Cap: at most eight visible corpses, oldest removed first.
        let (s2, _) = combatDuelScene()
        var made: [Being] = []
        for k in 0..<10 {
            var soul = Soul(id: 9100 + k, name: "C\(k)", faction: .hive, motive: .duty, backstory: "")
            soul.level = 1
            let b = Being(soul: soul, pos: CGPoint(x: s2.player.pos.x + 200, y: s2.player.pos.y), role: .hostile)
            s2.beings.append(b); s2.worldNode.addChild(b.node); s2.kill(b); made.append(b)
            advanceTest(s2, frames: 1, acts: [])
            s2.hitStop = 0
        }
        advanceTest(s2, frames: 1, acts: [])
        let visible = s2.beings.filter { $0.dead && $0.node.parent != nil }.count
        if visible > GameScene.corpseCap { failures.append("v3 combat: \(visible) corpses visible (cap \(GameScene.corpseCap))") }
        if made[0].node.parent != nil || made[9].node.parent == nil { failures.append("v3 combat: corpse cap did not remove oldest first") }
    }

    // Damage releases traversal; powers refuse to fire outside free movement; FX clamps.
    do {
        let (s, _) = combatDuelScene(dx: 300)
        let p = s.player!
        p.moveMode = .hang; p.invuln = 0
        s.hurtPlayer(5, from: nil)
        if p.moveMode != .free { failures.append("v3 combat: damage did not cancel traversal") }
        s.chron.powers = ["Blink"]; p.energy = 100; p.moveMode = .climb
        s.castPower()
        if p.energy != 100 { failures.append("v3 combat: power cast while not in free movement") }
        p.moveMode = .free
        s.impact(at: p.pos, dir: 1, stop: 0.01, shake: 40, color: .white, blood: false, heavy: true)
        if s.shake > 10 || abs(s.zoomPunch) > 0.035 + 1e-9 { failures.append("v3 combat: shake/zoom punch not clamped (\(s.shake), \(s.zoomPunch))") }
    }

    // Time-scaled lunge decay: 120 Hz covers the same distance as 60 Hz within tolerance.
    do {
        func lungeDistance(_ hz: Double) -> CGFloat {
            let (pl, w, i) = standalonePlayer()
            let x0 = pl.pos.x
            let n = Int(0.5 * hz)
            for f in 0..<n { i.synthetic = f == 0 ? [.attack] : []; i.poll(); pl.update(CGFloat(1.0 / hz), w, i) }
            return pl.pos.x - x0
        }
        let a = lungeDistance(60), b = lungeDistance(120)
        if abs(a - b) > max(4, abs(a) * 0.15) { failures.append("v3 combat: lunge distance frame-rate dependent (60Hz \(a), 120Hz \(b))") }
        notes.append(String(format: "lunge 60Hz %.1f / 120Hz %.1f", a, b))
    }

    print("  v3 combat        : kinds slash/thrust/overhead, guard break, recoil lock, corpse pass (\(notes.joined(separator: ", ")))")
}
