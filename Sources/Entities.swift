import SpriteKit

/// Axis-separated AABB vs tile collision, shared by every mover.
class Body {
    var pos: CGPoint            // bottom-center
    var vel = CGVector.zero
    let size: CGSize
    var onGround = false, wallDir = 0, dropThrough = 0.0
    let node = SKNode()

    init(pos: CGPoint, size: CGSize) { self.pos = pos; self.size = size }

    var rect: CGRect { CGRect(x: pos.x - size.width / 2, y: pos.y, width: size.width, height: size.height) }

    func step(_ dt: CGFloat, _ world: World, gravity: CGFloat = GRAVITY) {
        vel.dy = max(vel.dy + gravity * dt, -1400)
        dropThrough = max(0, dropThrough - Double(dt))
        pos.x += vel.dx * dt
        wallDir = 0
        var r = rect
        let y0 = Int((r.minY + 2) / T), y1 = Int((r.maxY - 2) / T)
        if vel.dx > 0 {
            let tx = Int(r.maxX / T)
            for ty in y0...y1 where world.at(tx, ty) == .solid { pos.x = CGFloat(tx) * T - size.width / 2 - 0.01; vel.dx = 0; wallDir = 1; break }
        } else if vel.dx < 0 {
            let tx = Int(r.minX / T)
            for ty in y0...y1 where world.at(tx, ty) == .solid { pos.x = CGFloat(tx + 1) * T + size.width / 2 + 0.01; vel.dx = 0; wallDir = -1; break }
        }
        if wallDir == 0 {
            r = rect
            let ym = Int(r.midY / T)
            if world.at(Int((r.maxX + 2) / T), ym) == .solid { wallDir = 1 }
            else if world.at(Int((r.minX - 2) / T), ym) == .solid { wallDir = -1 }
        }
        // Dynamic gates (v3 §6): horizontal push-out against closed gate rects.
        if !world.closedGateRects.isEmpty {
            r = rect
            for g in world.closedGateRects.values where World.overlaps(r, g) {
                if pos.x < g.midX { pos.x = g.minX - size.width / 2 - 0.01; wallDir = 1 } else { pos.x = g.maxX + size.width / 2 + 0.01; wallDir = -1 }
                vel.dx = 0; r = rect
            }
        }
        let prevBottom = pos.y
        pos.y += vel.dy * dt
        onGround = false
        r = rect
        let x0 = Int((r.minX + 2) / T), x1 = Int((r.maxX - 2) / T)
        if vel.dy <= 0 {
            let ty = Int(r.minY / T)
            for tx in x0...x1 {
                let t = world.at(tx, ty)
                let top = CGFloat(ty + 1) * T
                if t == .solid || t == .spike || (t == .ledge && dropThrough == 0 && prevBottom >= top - 1) {
                    pos.y = top; vel.dy = 0; onGround = true; break
                }
            }
        } else {
            let ty = Int(r.maxY / T)
            for tx in x0...x1 where world.at(tx, ty) == .solid { pos.y = CGFloat(ty) * T - size.height - 0.01; vel.dy = 0; break }
        }
        if !world.closedGateRects.isEmpty {
            r = rect
            for g in world.closedGateRects.values where World.overlaps(r, g) {
                if vel.dy <= 0 && prevBottom >= g.maxY - 1 { pos.y = g.maxY; vel.dy = 0; onGround = true }
                else if vel.dy > 0 && prevBottom + size.height <= g.minY + 1 { pos.y = g.minY - size.height - 0.01; vel.dy = 0 }
                r = rect
            }
        }
        node.position = pos
    }

    func standingOnSpike(_ world: World) -> Bool {
        onGround && world.at(Int(pos.x / T), Int((pos.y - 1) / T)) == .spike
    }
}

/// Attack phases, modelled on Prince of Persia's strike sequence (seqtbl.c):
/// anticipation (frame 168 back) -> contact (151-153) -> follow-through/recovery (154-157).
/// Recovery is deliberately longer than wind-up: that is what makes a swing feel committed.
enum Phase { case none, windup, active, recovery }

/// Directional attack selection: up+attack = overhead, down+attack = thrust, otherwise the slash chain.
enum AttackKind { case slash, thrust, overhead }

/// Traversal authority hook (free = ordinary physics). Hang/climb modes are owned by traversal code.
enum MoveMode { case free, hang, climb }

struct AttackSpec {
    let windup: Double, active: Double, recovery: Double
    let lunge: CGFloat, reach: CGFloat, damage: CGFloat, knock: CGFloat, hitStop: Double, shake: CGFloat
    var breaksGuard: Bool = false     // explicit; never inferred from damage
    static let light1 = AttackSpec(windup: 0.085, active: 0.075, recovery: 0.17, lunge: 230, reach: 58, damage: 1.0, knock: 240, hitStop: 0.055, shake: 5)
    static let light2 = AttackSpec(windup: 0.075, active: 0.075, recovery: 0.17, lunge: 260, reach: 60, damage: 1.1, knock: 260, hitStop: 0.06, shake: 6)
    static let heavy  = AttackSpec(windup: 0.17, active: 0.10, recovery: 0.32, lunge: 360, reach: 76, damage: 2.4, knock: 460, hitStop: 0.085, shake: 9, breaksGuard: true)
    static let thrust = AttackSpec(windup: 0.09, active: 0.07, recovery: 0.22, lunge: 260, reach: 78, damage: 0.90, knock: 180, hitStop: 0.045, shake: 4)
    static let overheadCost: CGFloat = 20
}

// MARK: - Player

final class Player: Body {
    var hp: CGFloat = 100, maxHP: CGFloat = 100
    var energy: CGFloat = 100
    var facing: CGFloat = 1
    var phase = Phase.none, phaseT = 0.0, combo = 0, bufferedAttack = 0.0
    var spec = AttackSpec.light1
    var attackKind = AttackKind.slash, bufferedKind = AttackKind.slash
    var recoilLock: Double = 0
    var comboGap = 1.0                 // gameplay seconds since the last attack ended (chain window)
    var moveMode = MoveMode.free {
        didSet {
            guard moveMode != oldValue else { return }
            if moveMode == .hang { onTraversal?(.grab, 1) } else if moveMode == .climb { onTraversal?(.climb, 1) }
        }
    }
    /// v3 §7 foley hook (step/land/grab/climb/draw); wired once in `buildDepth()`.
    var onTraversal: ((TraversalCue, Float) -> Void)?
    var strideDist: CGFloat = 0
    static let strideLength: CGFloat = 38
    private var capturedPoll: (ObjectIdentifier, Int)? = nil
    var swingId = 0
    var dashTimer = 0.0, dashCD = 0.0, invuln = 0.0
    var blocking = false, parryWindow = 0.0
    var wallRunTime = 0.0, coyote = 0.0, jumpBuffer = 0.0
    var hurtFlash = 0.0, hurtPose = 0.0, landSquash = 0.0
    var powerIndex = 0
    let rig: Rig
    private var runPhase: CGFloat = 0, clock: CGFloat = 0
    private var cur = Pose.guardStance
    private let shadow = SKSpriteNode(texture: Art.softGlow, size: CGSize(width: 44, height: 10))
    var onWhoosh: (() -> Void)?

    init(pos: CGPoint) {
        rig = Rig(RigStyle(skin: SKColor(red: 0.86, green: 0.66, blue: 0.48, alpha: 1),
                           cloth: SKColor(red: 0.93, green: 0.9, blue: 0.82, alpha: 1),
                           accent: SKColor(red: 0.8, green: 0.1, blue: 0.16, alpha: 1),
                           metal: SKColor(red: 0.85, green: 0.95, blue: 1, alpha: 1), scale: 0.92))
        super.init(pos: pos, size: CGSize(width: 22, height: 56))
        shadow.color = .black; shadow.colorBlendFactor = 1; shadow.alpha = 0.55; shadow.zPosition = -1
        node.addChild(shadow); node.addChild(rig.root)
        node.zPosition = 10
    }

    var attacking: Bool { phase != .none }
    var threatening: Bool { phase == .windup || phase == .active }

    /// Starts the buffered attack kind (slash by default). Overhead costs energy; if short, falls back to light1.
    func startAttack() {
        var kind = bufferedKind
        bufferedKind = .slash
        if kind == .slash {
            let chaining = phase != .none || comboGap < 0.3
            combo = chaining ? (combo + 1) % 3 : 0
            if combo == 2 { kind = .overhead }          // chain finisher
        } else {
            combo = -1                                   // direct thrust/overhead resets the chain
        }
        if kind == .overhead {
            if energy >= AttackSpec.overheadCost { energy -= AttackSpec.overheadCost }
            else { kind = .slash; combo = 0 }
        }
        attackKind = kind
        switch kind {
        case .slash: spec = combo == 1 ? .light2 : .light1
        case .thrust: spec = .thrust
        case .overhead: spec = .heavy
        }
        phase = .windup; phaseT = spec.windup
        if comboGap >= 1.5 { onTraversal?(.draw, 1) }      // first strike after 1.5 s idle: blade scrape
        comboGap = 0
        swingId += 1
    }

    /// Records an attack press and its directional modifier at press time. Safe to call more than once per
    /// poll (the scene calls it every poll, including during hit-stop; `update` calls it for standalone use).
    func captureAttack(_ inp: Input) {
        let key = (ObjectIdentifier(inp), inp.pollCount)
        if let c = capturedPoll, c.0 == key.0, c.1 == key.1 { return }
        capturedPoll = key
        guard inp.hit(.attack) && !blocking else { return }
        bufferedAttack = 0.25
        bufferedKind = inp.held(.up) ? .overhead : (inp.held(.down) ? .thrust : .slash)   // up wins
    }

    func discardAttackBuffer() { bufferedAttack = 0; bufferedKind = .slash }

    /// Leave any traversal mode and restore ordinary physics (damage, removed support).
    func cancelTraversal() {
        moveMode = .free
        discardAttackBuffer()
    }

    /// Our strike was blocked: PoP's "blockedstrike" drops straight into a long recovery.
    func recoil() { phase = .recovery; phaseT = 0.38; recoilLock = 0.38; combo = 0; vel.dx = -facing * 260; discardAttackBuffer() }

    func update(_ dt: CGFloat, _ w: World, _ inp: Input) {
        let d = Double(dt)
        clock += dt
        dashTimer = max(0, dashTimer - d); dashCD = max(0, dashCD - d); invuln = max(0, invuln - d)
        parryWindow = max(0, parryWindow - d); hurtFlash = max(0, hurtFlash - d); hurtPose = max(0, hurtPose - d)
        landSquash = max(0, landSquash - d); recoilLock = max(0, recoilLock - d)
        if phase == .none { comboGap += d }
        captureAttack(inp)
        let attackPress = inp.hit(.attack)
        if bufferedAttack > 0 { bufferedAttack = max(0, bufferedAttack - d); if bufferedAttack == 0 { bufferedKind = .slash } }
        coyote = onGround ? 0.1 : max(0, coyote - d)
        // An attack press owns this step: up/down are modifiers, so they must not also jump.
        jumpBuffer = (inp.hit(.jump) && !attackPress) ? 0.12 : max(0, jumpBuffer - d)
        energy = min(100, energy + 12 * dt)

        var dir: CGFloat = 0
        if inp.held(.left) { dir -= 1 }
        if inp.held(.right) { dir += 1 }
        if dir != 0 && phase == .none { facing = dir }

        // Attack state machine with input buffering (press during active/recovery chains the combo)
        if phase != .none {
            phaseT -= d
            if phaseT <= 0 {
                switch phase {
                case .windup:
                    phase = .active; phaseT = spec.active; onWhoosh?()
                    if onGround { vel.dx = facing * spec.lunge }
                case .active: phase = .recovery; phaseT = spec.recovery
                case .recovery: phase = .none; recoilLock = 0
                case .none: break
                }
            }
            // Cancel recovery into the next attack after 0.09 s (never the heavy recovery or a recoil)
            if chainOpen && bufferedAttack > 0 {
                bufferedAttack = 0; startAttack()
            }
        } else if bufferedAttack > 0 && recoilLock == 0 {
            bufferedAttack = 0
            if dir != 0 { facing = dir }
            startAttack()
        }

        let wasBlocking = blocking
        blocking = inp.held(.block) && onGround && dashTimer == 0 && phase == .none
        if blocking && !wasBlocking { parryWindow = 0.2 }

        if inp.hit(.dash) && dashCD == 0 && energy >= 15 && phase != .active && recoilLock == 0 {
            phase = .none
            dashTimer = 0.18; dashCD = 0.45; invuln = 0.22; energy -= 15
            if dir != 0 { facing = dir }
            vel.dx = facing * 900; vel.dy = max(vel.dy, 0)
        }

        if dashTimer > 0 {
            vel.dy = 0
        } else if phase == .active {
            vel.dx *= pow(0.86, dt * 60)   // lunge decays: weight (time-scaled; 0.86 per step at 60 Hz)
        } else if phase == .windup || (phase == .recovery) {
            vel.dx *= pow(0.80, dt * 60)   // rooted while committing
        } else {
            let speed: CGFloat = blocking ? 90 : 300
            let accel: CGFloat = onGround ? 3000 : 1600
            let target = dir * speed
            if vel.dx < target { vel.dx = min(target, vel.dx + accel * dt) } else { vel.dx = max(target, vel.dx - accel * dt) }
        }

        var wallRunning = false
        if !onGround && wallDir != 0 && dir == CGFloat(wallDir) && wallRunTime < 0.45 && dashTimer == 0 {
            wallRunTime += d; wallRunning = true
            vel.dy = max(vel.dy, 420 * CGFloat(1 - wallRunTime / 0.45))
        } else if !onGround && wallDir != 0 && dir == CGFloat(wallDir) {
            vel.dy = max(vel.dy, -120); wallRunning = true
        }
        if onGround { wallRunTime = 0 }

        if jumpBuffer > 0 && phase != .active && recoilLock == 0 {
            if coyote > 0 {
                if inp.held(.down) && w.at(Int(pos.x / T), Int((pos.y - 1) / T)) == .ledge { dropThrough = 0.25 }
                else { vel.dy = 760; phase = .none }
                jumpBuffer = 0; coyote = 0
            } else if wallDir != 0 {
                vel.dy = 700; vel.dx = CGFloat(-wallDir) * 420; facing = CGFloat(-wallDir)
                wallRunTime = 0.2; jumpBuffer = 0
            }
        }
        if !inp.held(.jump) && vel.dy > 300 && wallRunTime == 0 { vel.dy -= 2600 * dt }

        let wasAir = !onGround, fallSpeed = vel.dy, x0 = pos.x
        step(dt, w)
        if wasAir && onGround && fallSpeed < -500 { landSquash = 0.12 }
        emitFoley(wasAir: wasAir, fallSpeed: fallSpeed, dx: pos.x - x0)

        animate(dt, wallRunning: wallRunning)
    }

    /// Footsteps come only from grounded, actual displacement (blocked-against-wall moves ~0) and from
    /// air->ground contact crossings; never while hanging/climbing or airborne.
    private func emitFoley(wasAir: Bool, fallSpeed: CGFloat, dx: CGFloat) {
        guard moveMode == .free, onGround else { if !onGround { strideDist = Player.strideLength * 0.5 }; return }
        if wasAir {
            if fallSpeed < -260 { onTraversal?(.land, Float(clamp((-fallSpeed - 260) / 1100 + 0.35, 0.35, 1))) }
            else { onTraversal?(.step, 0.8) }
            strideDist = 0; return
        }
        guard dashTimer == 0, abs(dx) > 0.05 else { return }
        strideDist += abs(dx)
        if strideDist >= Player.strideLength { strideDist -= Player.strideLength; onTraversal?(.step, Float(clamp(abs(vel.dx) / 300, 0.4, 1))) }
    }

    private func animate(_ dt: CGFloat, wallRunning: Bool) {
        var target: Pose
        var rate: CGFloat = 16
        let heavy = attackKind == .overhead, thrust = attackKind == .thrust
        switch phase {
        case .windup:  target = heavy ? .heavyWindup : (thrust ? .thrustWindup : .windup); rate = 30
        case .active:  target = heavy ? .heavyStrike : (thrust ? .thrustStrike : .strike); rate = 60     // near-instant: reads as a smear
        case .recovery: target = .recover; rate = 9
        case .none:
            if hurtPose > 0 { target = .hurt; rate = 40 }
            else if dashTimer > 0 { target = .dash; rate = 40 }
            else if blocking { target = .block; rate = 30 }
            else if wallRunning { target = .wallRun; rate = 20 }
            else if !onGround { target = vel.dy > 0 ? .jump : .fall; rate = 12 }
            else if abs(vel.dx) > 40 {
                runPhase += dt * abs(vel.dx) / 300 * 11
                target = .run(runPhase); rate = 22
            } else { target = .breathe(clock); rate = 10 }
        }
        if combo == 1 && attackKind == .slash && phase != .none { target.shF += 0.25; target.sword -= 0.3 }   // second hit: different arc
        if landSquash > 0 { target.bodyY -= 7; target.knF -= 0.6; target.knB -= 0.6; target.hipF += 0.4 }
        cur = Pose.lerp(cur, target, min(1, rate * dt))
        rig.apply(cur, facing: facing)
        rig.flash(hurtFlash > 0 ? 0.85 : (invuln > 0 && dashTimer > 0 ? 0.4 : 0))
        rig.root.alpha = invuln > 0 && hurtFlash == 0 && dashTimer == 0 ? (Int(clock * 30) % 2 == 0 ? 1 : 0.5) : 1
        shadow.position = CGPoint(x: 0, y: 1); shadow.xScale = onGround ? 1 : 0.6
    }

    /// Active-frame hurtbox.
    var swing: CGRect? {
        guard phase == .active else { return nil }
        let reach = spec.reach
        let x = facing > 0 ? pos.x - 6 : pos.x - reach + 6
        switch attackKind {
        case .slash: return CGRect(x: x, y: pos.y + 2, width: reach, height: 52)
        case .thrust: return CGRect(x: x, y: pos.y + 22, width: reach, height: 22)      // narrow chest-height line
        case .overhead: return CGRect(x: x, y: pos.y + 2, width: reach, height: 66)     // tall arc over the head
        }
    }
    /// Light chaining opens 0.09 s into recovery; heavy recovery and recoil are uncancellable.
    var chainOpen: Bool { phase == .recovery && recoilLock == 0 && attackKind != .overhead && spec.recovery - phaseT >= 0.09 - 1e-9 }
    var swingDamage: CGFloat { spec.damage }
}

// MARK: - Beings: enemies, wanderers, allies

final class Being: Body {
    enum Role { case hostile, wanderer, ally, fleeing }
    var soul: Soul
    var role: Role
    var hp: CGFloat, maxHP: CGFloat
    var facing: CGFloat = 1
    var think = 0.0, cooldown = 0.0, stun = 0.0
    var phase = Phase.none, phaseT = 0.0, hitDone = false
    var blockT = 0.0, justBlocked = 0.0, justParried = 0.0, refrac = 0.0, aiTick = 0.0
    var lastHitSwing = -1
    var flashT = 0.0, hurtT = 0.0
    var bark: String? = nil
    var dead = false
    var deathT: Double = 0
    var hurtHigh = false
    var talked = false
    let rig: Rig
    let tint: SKColor
    let hpBar = SKSpriteNode(color: .red, size: CGSize(width: 30, height: 3))
    let nameTag: SKLabelNode
    private var cur = Pose.guardStance, runPhase: CGFloat = 0, clock: CGFloat = Art.vrand(0...10)
    var onWhoosh: (() -> Void)?

    // PoP guard skill tables (data.h), 0-255 per skill level, sampled at PoP's 12 Hz AI tick.
    static let strikeprob:  [Int] = [61, 100, 61, 61, 61, 40, 100, 220]
    static let restrikeprob:[Int] = [0, 0, 0, 5, 5, 175, 16, 8]
    static let blockprob:   [Int] = [0, 150, 150, 200, 200, 255, 200, 250]
    static let impblockprob:[Int] = [0, 61, 61, 100, 100, 145, 100, 250]
    static let advprob:     [Int] = [255, 200, 200, 200, 255, 255, 200, 0]
    static let refractimer: [Int] = [16, 16, 16, 16, 8, 8, 8, 8]

    var skill: Int { clamp(soul.level / 2 + soul.grudge, 0, 7) }

    init(soul: Soul, pos: CGPoint, role: Role) {
        self.soul = soul; self.role = role
        let base: CGFloat
        let style: RigStyle
        let sz: CGSize
        switch soul.faction {
        case .hive:
            base = 18
            tint = SKColor(red: 0.62, green: 0.2, blue: 0.55, alpha: 1)
            style = RigStyle(skin: SKColor(red: 0.42, green: 0.16, blue: 0.4, alpha: 1), cloth: SKColor(red: 0.3, green: 0.1, blue: 0.28, alpha: 1),
                             accent: SKColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1), metal: SKColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 1),
                             scale: 0.66, bulk: 1.25, weapon: .claws, turban: false, cape: false, crouch: 9)
            sz = CGSize(width: 26, height: 30)
        case .wardens:
            base = 38
            tint = SKColor(red: 0.45, green: 0.58, blue: 0.75, alpha: 1)
            style = RigStyle(skin: SKColor(red: 0.6, green: 0.45, blue: 0.35, alpha: 1), cloth: SKColor(red: 0.3, green: 0.38, blue: 0.52, alpha: 1),
                             accent: SKColor(red: 0.75, green: 0.6, blue: 0.25, alpha: 1), metal: SKColor(red: 0.75, green: 0.8, blue: 0.9, alpha: 1),
                             scale: 0.84, bulk: 1.45, weapon: .glaive, turban: false)
            sz = CGSize(width: 28, height: 50)
        case .echoes:
            base = 24
            tint = SKColor(red: 0.98, green: 0.82, blue: 0.35, alpha: 1)
            style = RigStyle(skin: SKColor(red: 0.55, green: 0.6, blue: 0.75, alpha: 1), cloth: SKColor(red: 0.85, green: 0.7, blue: 0.3, alpha: 1),
                             accent: SKColor(red: 0.3, green: 0.8, blue: 1, alpha: 1), metal: SKColor(red: 0.6, green: 0.9, blue: 1, alpha: 1),
                             scale: 0.78, bulk: 0.9, weapon: .staff, turban: true)
            sz = CGSize(width: 20, height: 46)
        }
        rig = Rig(style)
        maxHP = base + CGFloat(soul.level) * 8 + CGFloat(soul.grudge) * 10
        hp = maxHP
        nameTag = label(soul.name, size: 10, color: .white)
        super.init(pos: pos, size: sz)
        node.addChild(rig.root)
        let sh = SKSpriteNode(texture: Art.softGlow, size: CGSize(width: sz.width * 1.8, height: 10))
        sh.color = .black; sh.colorBlendFactor = 1; sh.alpha = 0.5; sh.zPosition = -1; node.addChild(sh)
        if soul.grudge > 0 {   // nemesis aura
            let aura = SKSpriteNode(texture: Art.softGlow, size: CGSize(width: 90, height: 110))
            aura.color = .red; aura.colorBlendFactor = 1; aura.alpha = 0.35; aura.blendMode = .add; aura.position = CGPoint(x: 0, y: sz.height / 2); aura.zPosition = -2
            aura.run(.repeatForever(.sequence([.fadeAlpha(to: 0.15, duration: 0.7), .fadeAlpha(to: 0.4, duration: 0.7)])))
            node.addChild(aura)
        }
        hpBar.anchorPoint = CGPoint(x: 0, y: 0.5); hpBar.position = CGPoint(x: -15, y: rig.height * 0.9 + 6)
        nameTag.position = CGPoint(x: 0, y: rig.height * 0.9 + 16)
        node.addChild(hpBar); node.addChild(nameTag)
        node.zPosition = 9
        restyle()
    }

    func restyle() {
        switch role {
        case .ally: nameTag.fontColor = SKColor(red: 0.4, green: 1, blue: 0.6, alpha: 1)
        case .wanderer: nameTag.fontColor = SKColor(red: 0.6, green: 0.8, blue: 1, alpha: 1)
        case .fleeing: nameTag.fontColor = .gray
        case .hostile: nameTag.fontColor = soul.grudge > 0 ? .red : .white
        }
    }

    var attackRange: CGFloat { soul.faction == .echoes ? 320 : (soul.faction == .hive ? 44 : 62) }
    var blocking: Bool { blockT > 0 }
    var windupTime: Double { soul.faction == .wardens ? 0.42 : (soul.faction == .hive ? 0.26 : 0.38) }

    func parried() { stun = 1.0; phase = .none; hitDone = true; vel.dx = -facing * 240 }
    func hitReact(knock: CGFloat, dir: CGFloat) { hitReact(knock: knock, dir: dir, high: false) }
    func hitReact(knock: CGFloat, dir: CGFloat, high: Bool) {
        flashT = 0.08; hurtT = 0.22; phase = .none; hurtHigh = high
        vel.dx = dir * knock; vel.dy = 160 + knock * 0.25
        refrac = Double(Being.refractimer[skill]) / 12.0     // PoP guard_refrac
    }
    /// Guard broken by a heavy: guard drops, attack aborts, brief stagger. Distinct from `parried()`.
    func breakGuard(dir: CGFloat) {
        blockT = 0; phase = .none; hitDone = true; stun = 0.45; justBlocked = 0; hurtHigh = true
        flashT = 0.08; vel.dx = dir * 200
    }
    /// Corpse pass: collision-aware fall, 0.30 s collapse into `.dead`, then settle. No AI, no melee.
    func updateDeath(_ dt: CGFloat, _ world: World) {
        deathT += Double(dt)
        if deathT > 0.30 && onGround { vel = .zero } else { vel.dx *= pow(0.85, dt * 60) }
        if !(deathT > 0.30 && onGround) { step(dt, world) }   // settled corpses never bounce
        else { node.position = pos }
        flashT = max(0, flashT - Double(dt)); hurtT = 0; stun = 0; blockT = 0; phase = .none
        animate(dt)
        hpBar.isHidden = true
    }
    func blockedHit() { justBlocked = 0.5; justParried = 0.6; blockT = 0.2; vel.dx = -facing * 120 }

    /// Behavior = faction + motive + PoP duel logic for melee factions.
    func update(_ dt: CGFloat, _ w: World, target: CGPoint?, playerPos: CGPoint, threat: Bool, r: inout RNG) -> (melee: CGRect?, bolt: CGVector?) {
        let d = Double(dt)
        clock += dt
        think -= d; cooldown = max(0, cooldown - d); stun = max(0, stun - d)
        blockT = max(0, blockT - d); justBlocked = max(0, justBlocked - d); justParried = max(0, justParried - d)
        refrac = max(0, refrac - d); flashT = max(0, flashT - d); hurtT = max(0, hurtT - d)
        var melee: CGRect? = nil, bolt: CGVector? = nil
        var desired: CGFloat = 0
        let speed: CGFloat = soul.faction == .hive ? 260 : (soul.faction == .wardens ? 130 : 160)

        // Advance the attack timeline
        if phase != .none {
            phaseT -= d
            if phaseT <= 0 {
                switch phase {
                case .windup:
                    phase = .active; phaseT = 0.1; hitDone = false; onWhoosh?()
                    if soul.faction == .hive { vel.dx = facing * 520; vel.dy = 280 }
                    else if soul.faction == .wardens { vel.dx = facing * 260 }
                case .active: phase = .recovery; phaseT = soul.faction == .wardens ? 0.5 : 0.36
                case .recovery: phase = .none
                case .none: break
                }
            }
        }
        if stun > 0 || hurtT > 0 { if phase == .windup { phase = .none } }

        if stun > 0 || hurtT > 0 {
            desired = 0
        } else if role == .fleeing {
            desired = playerPos.x < pos.x ? 1 : -1
        } else if role == .wanderer {
            if think <= 0 { think = 2 + r.unit() * 3; facing = r.chance(0.5) ? 1 : -1 }
            desired = abs(playerPos.x - pos.x) < 80 ? 0 : facing * 0.25
        } else if let t = target {
            let dx = t.x - pos.x, dist = hypot(dx, t.y - pos.y)
            if phase == .none { facing = dx >= 0 ? 1 : -1 }
            let sameLevel = abs(t.y - pos.y) < 90

            if soul.faction == .echoes {
                var keep: CGFloat = attackRange * 0.7
                if soul.motive == .fear && role == .hostile { keep = 220 }
                if dist > keep { desired = facing } else if dist < keep * 0.5 { desired = -facing }
                if phase == .none && dist < attackRange + 20 && cooldown == 0 && sameLevel { phase = .windup; phaseT = windupTime }
                if phase == .active && !hitDone {
                    hitDone = true
                    let ty = t.y + 20 - (pos.y + 34)
                    let n = max(1, hypot(dx, ty))
                    bolt = CGVector(dx: dx / n * 430, dy: ty / n * 430)
                    cooldown = 1.8
                }
                if dist < 60 && cooldown == 0 && r.chance(0.02) {
                    let nx = pos.x - facing * 160
                    if w.at(Int(nx / T), Int((pos.y + 10) / T)) == .empty { pos.x = nx; cooldown = 0.8 }
                }
            } else {
                // PoP autocontrol_guard_kid_armed, distances scaled to our units.
                aiTick -= d
                if aiTick <= 0 && phase == .none {
                    aiTick = 1.0 / 12.0
                    let sk = skill
                    var strikeP = Being.strikeprob[sk], blockP = Being.blockprob[sk]
                    switch soul.motive {
                    case .vengeance: strikeP = min(255, strikeP + 70)
                    case .fear: strikeP /= 2; blockP = min(255, blockP + 50)
                    case .duty: blockP = min(255, blockP + 40)
                    case .hunger: strikeP = min(255, strikeP + 40)
                    default: break
                    }
                    let tooClose: CGFloat = 22, band = attackRange + 14
                    if dist < tooClose || dist >= band {
                        if Being.advprob[sk] + (soul.faction == .hive ? 60 : 0) > r.int(255) || dist >= band { desired = facing }
                    } else if sameLevel {
                        if threat && blockT == 0 {
                            let p = justBlocked > 0 ? Being.impblockprob[sk] : blockP
                            if p > r.int(255) { blockT = 0.32 }
                        }
                        if refrac == 0 && blockT == 0 && cooldown == 0 {
                            let p = justParried > 0 ? max(Being.restrikeprob[sk], strikeP / 2) : strikeP
                            if p > r.int(255) { phase = .windup; phaseT = windupTime; cooldown = 0.3 }
                        }
                    }
                    if soul.motive == .fear && role == .hostile && dist < 120 { desired = -facing * 0.5 }
                    if soul.faction == .wardens && soul.motive == .duty && dist > 260 { desired = 0 }
                    think = 0
                    lastDesired = desired
                } else if phase == .none { desired = lastDesired }

                if phase == .active && !hitDone {
                    hitDone = true
                    let reach = attackRange + 12
                    melee = CGRect(x: facing > 0 ? pos.x - 4 : pos.x - reach + 4, y: pos.y, width: reach, height: size.height + 10)
                }
            }
            if onGround && (t.y > pos.y + 60 || wallDir != 0) && phase == .none && r.chance(0.04) { vel.dy = 700 }
        }

        let tv = desired * speed
        if phase == .none && stun == 0 && hurtT == 0 && blockT == 0 {
            vel.dx += (tv - vel.dx) * min(1, 8 * dt)
        } else { vel.dx *= 0.88 }
        step(dt, w)
        animate(dt)
        hpBar.xScale = max(0, hp / maxHP)
        hpBar.isHidden = role == .wanderer
        return (melee, bolt)
    }
    private var lastDesired: CGFloat = 0

    private func animate(_ dt: CGFloat) {
        var target: Pose, rate: CGFloat = 14
        if dead { target = deathT < 0.30 ? Pose.lerp(.hurtHigh, .dead, CGFloat(deathT / 0.30)) : .dead; rate = deathT < 0.30 ? 30 : 8 }
        else if hurtT > 0 { target = hurtHigh ? .hurtHigh : .hurt; rate = 40 }
        else if stun > 0 { target = .hurt; target.torso += 0.2 * sin(clock * 9); rate = 12 }
        else {
            switch phase {
            case .windup: target = soul.faction == .wardens ? .heavyWindup : .windup; rate = 14   // slower = readable telegraph
            case .active: target = soul.faction == .wardens ? .heavyStrike : .strike; rate = 60
            case .recovery: target = .recover; rate = 8
            case .none:
                if blockT > 0 { target = .block; rate = 30 }
                else if !onGround { target = .fall }
                else if abs(vel.dx) > 30 { runPhase += dt * abs(vel.dx) / 260 * 11; target = .run(runPhase); rate = 20 }
                else { target = .breathe(clock) }
            }
        }
        if soul.faction == .echoes && phase == .windup { target.shF = 2.8; target.sword = 1.6 }   // staff raised to cast
        cur = Pose.lerp(cur, target, min(1, rate * dt))
        rig.apply(cur, facing: facing)
        rig.flash(flashT > 0 ? 1 : (phase == .windup ? 0.25 + 0.25 * sin(clock * 40) : 0))
    }
}

final class Bolt {
    var pos: CGPoint, vel: CGVector, life = 2.0
    let friendly: Bool, dmg: CGFloat
    let node: SKNode
    init(pos: CGPoint, vel: CGVector, friendly: Bool, dmg: CGFloat, color: SKColor) {
        self.pos = pos; self.vel = vel; self.friendly = friendly; self.dmg = dmg
        let n = SKNode()
        let core = SKSpriteNode(texture: Art.spark, size: CGSize(width: 18, height: 18)); core.blendMode = .add
        let halo = SKSpriteNode(texture: Art.softGlow, size: CGSize(width: 64, height: 64))
        halo.color = color; halo.colorBlendFactor = 1; halo.blendMode = .add; halo.alpha = 0.7
        let tail = SKEmitterNode()
        tail.particleTexture = Art.spark; tail.particleBirthRate = 90; tail.particleLifetime = 0.3
        tail.particleScale = 0.6; tail.particleScaleSpeed = -1.8; tail.particleColor = color; tail.particleColorBlendFactor = 1
        tail.particleBlendMode = .add; tail.particleAlphaSpeed = -3
        n.addChild(halo); n.addChild(core); n.addChild(tail)
        let light = SKLightNode(); light.categoryBitMask = 1; light.lightColor = color; light.falloff = 2.2; light.ambientColor = .clear
        n.addChild(light)
        node = n; node.position = pos; node.zPosition = 11
        tail.targetNode = nil
    }
}
