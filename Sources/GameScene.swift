import SpriteKit

/// The rift: one procedurally generated depth. Owns entities, combat, dialogue, HUD and the portal.
final class GameScene: SKScene {
    /// Test sessions (fixtures/v3 selftest) use an in-memory Chronicle and never touch the user's save.
    var isTestSession = false
    private(set) var loadedFromDisk = false, persistCount = 0
    lazy var chron: Chronicle = {
        if isTestSession { return Chronicle() }
        loadedFromDisk = true
        return Chronicle.load()
    }()
    /// Optional fixture layout hook: runs on the freshly generated World before baking/spawning.
    var fixtureLayout: ((World) -> Void)?
    /// When set, visual-only randomness (shake, sparks, slash angle) is drawn from this seeded stream.
    var visRng: RNG?
    /// Freezes the live update loop (and actions) so a snapshot captures a settled, deterministic frame.
    var simFrozen = false
    var world: World!
    var theme: Theme!
    var rng = RNG(1)
    let worldNode = SKNode()
    let cam = SKCameraNode()
    let hud = SKNode()
    var player: Player!
    var beings: [Being] = []
    var bolts: [Bolt] = []
    var props: [(kind: Spawn.Kind, node: SKNode, used: Bool)] = []
    var portalNode: SKNode!
    weak var synth: Synth?
    let input = Input.shared

    // UI state
    enum Mode { case play, dialogue, portal, dead, paused }
    var mode: Mode = .play
    var talkingTo: Being?
    var dialogueOptions: [String] = []
    var portalOptions: [(String, String)] = []
    var slowTime = 0.0, overcharge = 0.0
    var shake: CGFloat = 0, shakeDir: CGFloat = 0, zoomPunch: CGFloat = 0
    var hitStop = 0.0, slowMoT = 0.0, damageVignette: CGFloat = 0
    var camBase = CGPoint.zero
    let parallaxFar = SKNode(), parallaxMid = SKNode()
    let vignette = SKSpriteNode(texture: Art.vignette)
    let hurtOverlay = SKSpriteNode(texture: Art.vignette)
    var lastTime: TimeInterval = 0
    var lastBuildMs = 0.0
    var stats = (kills: 0, spared: 0, talks: 0, portals: 0, frames: 0)
    var combat = (hits: 0, blockedByFoe: 0, playerBlocks: 0, parries: 0, hitStopFrames: 0, guardBreaks: 0)
    var toast: [(SKLabelNode, Double)] = []

    // HUD nodes
    let hpBar = SKSpriteNode(color: SKColor(red: 0.9, green: 0.15, blue: 0.2, alpha: 1), size: CGSize(width: 220, height: 12))
    let enBar = SKSpriteNode(color: SKColor(red: 0.2, green: 0.7, blue: 1, alpha: 1), size: CGSize(width: 220, height: 6))
    let info = label("", size: 13)
    let title = label("", size: 18, bold: true)
    let powerLabel = label("", size: 12)
    let panel = SKShapeNode()
    let panelText = SKLabelNode(fontNamed: "Menlo")
    let hint = label("", size: 12, color: SKColor(white: 1, alpha: 0.75))
    let hpBack = SKSpriteNode(color: SKColor(white: 0.1, alpha: 0.9), size: CGSize(width: 224, height: 16))
    let enBack = SKSpriteNode(color: SKColor(white: 0.1, alpha: 0.9), size: CGSize(width: 224, height: 10))

    override func didMove(to view: SKView) { setup() }

    func setup() {
        guard world == nil else { return }
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(worldNode)
        addChild(cam); camera = cam
        cam.addChild(parallaxFar); parallaxFar.zPosition = -100
        worldNode.addChild(parallaxMid)
        vignette.zPosition = 90; vignette.alpha = 0.9; cam.addChild(vignette)
        hurtOverlay.zPosition = 91; hurtOverlay.color = .red; hurtOverlay.colorBlendFactor = 1; hurtOverlay.alpha = 0; hurtOverlay.blendMode = .add
        cam.addChild(hurtOverlay)
        cam.addChild(hud); hud.zPosition = 100
        // Styled HUD plate (ornate dark panel with gold rule) behind bars and stats
        let plate = SKShapeNode(rectOf: CGSize(width: 470, height: 86), cornerRadius: 8)
        plate.fillColor = SKColor(white: 0, alpha: 0.55); plate.strokeColor = SKColor(red: 0.85, green: 0.68, blue: 0.3, alpha: 0.7); plate.lineWidth = 1.5
        plate.name = "plate"; plate.zPosition = -1; hud.addChild(plate)
        let hintPlate = SKShapeNode(rectOf: CGSize(width: 900, height: 24), cornerRadius: 12)
        hintPlate.fillColor = SKColor(white: 0, alpha: 0.5); hintPlate.strokeColor = .clear; hintPlate.name = "hintPlate"; hintPlate.zPosition = -1
        hud.addChild(hintPlate)
        for n in [hpBack, enBack] { n.anchorPoint = CGPoint(x: 0, y: 0.5); n.zPosition = -0.5; hud.addChild(n) }
        title.fontName = "Georgia-Bold"; title.fontSize = 26
        title.fontColor = SKColor(red: 0.98, green: 0.88, blue: 0.62, alpha: 1)
        for n in [hpBar, enBar] { n.anchorPoint = CGPoint(x: 0, y: 0.5); hud.addChild(n) }
        info.horizontalAlignmentMode = .left; powerLabel.horizontalAlignmentMode = .left
        hud.addChild(info); hud.addChild(title); hud.addChild(powerLabel); hud.addChild(hint)
        panel.fillColor = SKColor(white: 0, alpha: 0.82); panel.strokeColor = SKColor(white: 1, alpha: 0.4)
        panelText.numberOfLines = 0; panelText.fontSize = 15; panelText.preferredMaxLayoutWidth = 700
        panelText.horizontalAlignmentMode = .center; panelText.verticalAlignmentMode = .center
        panel.addChild(panelText); panel.isHidden = true; hud.addChild(panel)
        buildDepth()
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutHUD() }

    func layoutHUD() {
        let w = size.width / 2, h = size.height / 2
        hpBar.position = CGPoint(x: -w + 22, y: h - 24)
        enBar.position = CGPoint(x: -w + 22, y: h - 40)
        hpBack.position = CGPoint(x: -w + 20, y: h - 24); enBack.position = CGPoint(x: -w + 20, y: h - 40)
        info.position = CGPoint(x: -w + 22, y: h - 60)
        powerLabel.position = CGPoint(x: -w + 22, y: h - 78)
        hud.childNode(withName: "plate")?.position = CGPoint(x: -w + 245, y: h - 50)
        hud.childNode(withName: "hintPlate")?.position = CGPoint(x: 0, y: -h + 22)
        title.position = CGPoint(x: 0, y: h - 34)
        hint.position = CGPoint(x: 0, y: -h + 22)
        panel.path = CGPath(roundedRect: CGRect(x: -380, y: -150, width: 760, height: 220), cornerWidth: 10, cornerHeight: 10, transform: nil)
        panel.position = CGPoint(x: 0, y: -h + 200)
        vignette.size = CGSize(width: size.width * 1.15, height: size.height * 1.15)
        hurtOverlay.size = vignette.size
    }

    // MARK: Depth generation

    func buildDepth() {
        let buildStart = Date()
        defer { lastBuildMs = Date().timeIntervalSince(buildStart) * 1000; if ProcessInfo.processInfo.environment["RIFTBORN_PROFILE"] != nil { print(String(format: "buildDepth %.0f ms", lastBuildMs)) } }
        worldNode.removeAllChildren(); beings.removeAll(); bolts.removeAll(); props.removeAll()
        rng = RNG(chron.seed &+ UInt64(chron.depth) &* 104729)
        theme = makeTheme(&rng, depth: chron.depth)
        if chron.mutator == "Maddening Depths" {
            theme = Theme(name: theme.name + " (Maddening)", sky: .black, rock: theme.rock.blended(withFraction: 0.5, of: .black) ?? theme.rock,
                          edge: SKColor(red: 1, green: 0.1, blue: 0.3, alpha: 1), mist: theme.mist)
        }
        pruneSouls()
        backgroundColor = theme.sky
        world = Prof.time("worldgen") { World(seed: chron.seed, depth: chron.depth) }
        if let layout = fixtureLayout { layout(world) }
        torchSpots = world.torchSpots()
        worldNode.addChild(Prof.time("bake tiles") { world.buildNode(theme: theme, lights: torchSpots) })
        worldNode.addChild(parallaxMid)
        Prof.time("parallax") { addParallax() }
        Prof.time("lighting") { addLighting() }
        if let s = synth {
            // Test sessions must not let audio presence perturb the simulation RNG stream.
            if isTestSession { var r2 = rng; s.reseed(&r2) } else { s.reseed(&rng) }
        }

        player = Player(pos: CGPoint(x: (CGFloat(world.start.x) + 0.5) * T, y: CGFloat(world.start.y) * T))
        player.maxHP = CGFloat(chron.maxHP); player.hp = player.maxHP
        player.onWhoosh = { [weak self] in self?.synth?.sfxWhoosh = (self?.player.attackKind == .overhead) ? 1.5 : 1 }
        worldNode.addChild(player.node)
        camBase = CGPoint(x: player.pos.x, y: player.pos.y + 70)

        // Returning souls: those with grudges or debts seek you out in later depths.
        var returning = chron.souls.filter { $0.alive && ($0.grudge > 0 || $0.debt > 0) }.shuffledWith(&rng)
        let mut = chron.mutator
        for var sp in world.spawns {
            // Mutator reshaping of the spawn table
            if mut == "Pilgrim's Road" && sp.kind == .chest && rng.chance(0.6) { sp = Spawn(kind: .shrine, x: sp.x, y: sp.y) }
            if mut == "Echoing Silence" && sp.kind == .enemy && rng.chance(0.5) { sp = Spawn(kind: .wanderer, x: sp.x, y: sp.y) }
            let p = CGPoint(x: (CGFloat(sp.x) + 0.5) * T, y: CGFloat(sp.y) * T)
            switch sp.kind {
            case .enemy:
                var soul: Soul
                if !returning.isEmpty && rng.chance(0.5) { soul = returning.removeFirst() }
                else if let dead = chron.souls.filter({ !$0.alive }).last, rng.chance(0.2),
                        !chron.souls.contains(where: { $0.kinOf == dead.id }) {
                    soul = Mind.newSoul(&chron, &rng, faction: dead.faction, motive: .vengeance, kinOf: dead.id)
                } else {
                    let biasHive = chron.repOf(.hive) < -4 && rng.chance(0.5)
                    soul = Mind.newSoul(&chron, &rng, faction: biasHive ? .hive : nil)
                }
                if chron.mutator == "Hive Ascendant" && rng.chance(0.4) { soul.faction = .hive }
                if mut == "Maddening Depths" { soul.level += 1 }
                var role: Being.Role = soul.debt > 0 && soul.grudge == 0 ? .ally : .hostile
                if mut == "Warden's Oath" && soul.faction == .wardens && soul.grudge == 0 && chron.repOf(.wardens) > -3 && rng.chance(0.5) { role = .ally }
                spawnBeing(soul, at: p, role: role)
            case .wanderer:
                let s = Mind.newSoul(&chron, &rng, motive: rng.pick([.curiosity, .redemption, .fear, .faith]))
                spawnBeing(s, at: p, role: .wanderer)
            case .shrine:
                let n = SKNode(); n.position = CGPoint(x: p.x, y: p.y + 20)
                let plinth = SKSpriteNode(texture: Rig.capsule, size: CGSize(width: 26, height: 44))
                plinth.color = theme.rock.blended(withFraction: 0.3, of: .white)!; plinth.colorBlendFactor = 1; plinth.lightingBitMask = 1
                let gem = SKSpriteNode(texture: Art.softGlow, size: CGSize(width: 70, height: 70))
                gem.color = theme.edge; gem.colorBlendFactor = 1; gem.blendMode = .add; gem.position = CGPoint(x: 0, y: 30)
                gem.run(.repeatForever(.sequence([.scale(to: 0.75, duration: 0.9), .scale(to: 1.05, duration: 0.9)])))
                let l = SKLightNode(); l.categoryBitMask = 1; l.lightColor = theme.edge; l.falloff = 2.0; l.ambientColor = .clear; l.position = CGPoint(x: 0, y: 30)
                n.addChild(plinth); n.addChild(gem); n.addChild(l)
                worldNode.addChild(n)
                props.append((.shrine, n, false))
            case .chest:
                let n = SKNode(); n.position = CGPoint(x: p.x, y: p.y + 10)
                let box = SKSpriteNode(color: SKColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1), size: CGSize(width: 30, height: 20)); box.lightingBitMask = 1
                let lid = SKSpriteNode(color: SKColor(red: 0.85, green: 0.65, blue: 0.2, alpha: 1), size: CGSize(width: 32, height: 6)); lid.position = CGPoint(x: 0, y: 10); lid.lightingBitMask = 1
                let glint = SKSpriteNode(texture: Art.spark, size: CGSize(width: 14, height: 14)); glint.blendMode = .add; glint.position = CGPoint(x: 8, y: 12)
                glint.run(.repeatForever(.sequence([.fadeAlpha(to: 0, duration: 0.8), .fadeAlpha(to: 1, duration: 0.2), .wait(forDuration: 1.5)])))
                n.addChild(box); n.addChild(lid); n.addChild(glint)
                worldNode.addChild(n)
                props.append((.chest, n, false))
            }
        }
        // Portal: swirling rift with particles and its own light
        let pp = CGPoint(x: (CGFloat(world.portal.x) + 0.5) * T, y: CGFloat(world.portal.y) * T + 50)
        portalNode = SKNode(); portalNode.position = pp
        let swirl = SKEmitterNode()
        swirl.particleTexture = Art.spark; swirl.particleBirthRate = 120; swirl.particleLifetime = 1.2
        swirl.particlePositionRange = CGVector(dx: 50, dy: 90); swirl.particleSpeed = 20; swirl.emissionAngleRange = .pi * 2
        swirl.particleScale = 0.5; swirl.particleScaleSpeed = -0.4; swirl.particleColor = theme.edge; swirl.particleColorBlendFactor = 1
        swirl.particleBlendMode = .add; swirl.particleAlphaSpeed = -0.8
        portalNode.addChild(swirl)
        for i in 0..<3 {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 64 - CGFloat(i) * 14, height: 104 - CGFloat(i) * 20))
            ring.strokeColor = theme.edge; ring.lineWidth = 3; ring.glowWidth = 12; ring.blendMode = .add
            ring.fillColor = i == 2 ? SKColor(white: 1, alpha: 0.12) : .clear
            ring.run(.repeatForever(.sequence([.scale(to: 1.1, duration: 0.6 + Double(i) * 0.2), .scale(to: 0.92, duration: 0.6 + Double(i) * 0.2)])))
            portalNode.addChild(ring)
        }
        let pl = SKLightNode(); pl.categoryBitMask = 1; pl.lightColor = theme.edge; pl.falloff = 1.2; pl.ambientColor = .clear
        portalNode.addChild(pl)
        worldNode.addChild(portalNode)

        title.text = theme.name
        title.alpha = 1; title.run(.sequence([.wait(forDuration: 4), .fadeAlpha(to: 0.35, duration: 1.5)]))
        layoutHUD()
        say(chron.depth == 1 && chron.log.isEmpty ? "A rift opens. Every soul here remembers." : "Mutator: \(chron.mutator)")
        saveChronicle()
    }

    /// Single persistence choke point: test sessions never write the production save.
    func saveChronicle() {
        guard !isTestSession else { return }
        persistCount += 1
        chron.save()
    }

    /// Enter an isolated test session with an in-memory Chronicle. Call before `setup()`.
    func beginTestSession(seed: UInt64, depth: Int = 1) {
        isTestSession = true
        var c = Chronicle(); c.seed = seed; c.depth = depth
        chron = c
        visRng = RNG(seed ^ 0x5649_5355_414C)
        Art.visRng = RNG(seed ^ 0x4152_5456_4953)
    }

    /// Visual-only random value; deterministic in test sessions.
    func vrand(_ r: ClosedRange<CGFloat>) -> CGFloat {
        guard visRng != nil else { return CGFloat.random(in: r) }
        return r.lowerBound + (r.upperBound - r.lowerBound) * CGFloat(visRng!.unit())
    }

    func addParallax() {
        // Far layer (camera-attached): night-sky gradient, moon, distant palace domes & minarets
        parallaxFar.removeAllChildren()
        let sky = SKSpriteNode(texture: Art.skyGradient(theme.sky.blended(withFraction: 0.3, of: .black)!, theme.mist), size: CGSize(width: 4000, height: 2400))
        sky.zPosition = -3; parallaxFar.addChild(sky)
        let moon = SKSpriteNode(texture: Art.softGlow, size: CGSize(width: 260, height: 260)); moon.position = CGPoint(x: 380, y: 260)
        moon.color = SKColor(red: 1, green: 0.95, blue: 0.85, alpha: 1); moon.colorBlendFactor = 1; moon.alpha = 0.55; moon.blendMode = .add; moon.zPosition = -2
        let disc = SKShapeNode(circleOfRadius: 38); disc.fillColor = SKColor(red: 1, green: 0.97, blue: 0.88, alpha: 0.9); disc.strokeColor = .clear; disc.position = moon.position; disc.zPosition = -2
        parallaxFar.addChild(moon); parallaxFar.addChild(disc)
        let skyline = CGMutablePath()
        var x: CGFloat = -2200
        skyline.move(to: CGPoint(x: x, y: -900))
        while x < 2200 {
            let bw = CGFloat(rng.range(80, 220)), bh = CGFloat(rng.range(-260, 40))
            skyline.addLine(to: CGPoint(x: x, y: bh))
            if rng.chance(0.4) {   // onion dome
                skyline.addQuadCurve(to: CGPoint(x: x + bw / 2, y: bh + bw * 0.7), control: CGPoint(x: x - bw * 0.1, y: bh + bw * 0.45))
                skyline.addQuadCurve(to: CGPoint(x: x + bw, y: bh), control: CGPoint(x: x + bw * 1.1, y: bh + bw * 0.45))
            } else if rng.chance(0.4) {   // minaret
                skyline.addLine(to: CGPoint(x: x + bw * 0.4, y: bh)); skyline.addLine(to: CGPoint(x: x + bw * 0.45, y: bh + 220))
                skyline.addLine(to: CGPoint(x: x + bw * 0.5, y: bh + 260)); skyline.addLine(to: CGPoint(x: x + bw * 0.55, y: bh + 220))
                skyline.addLine(to: CGPoint(x: x + bw * 0.6, y: bh)); skyline.addLine(to: CGPoint(x: x + bw, y: bh))
            } else { skyline.addLine(to: CGPoint(x: x + bw, y: bh)) }
            x += bw
        }
        skyline.addLine(to: CGPoint(x: x, y: -900)); skyline.closeSubpath()
        let sk = SKShapeNode(path: skyline); sk.fillColor = theme.sky.blended(withFraction: 0.5, of: .black)!; sk.strokeColor = .clear; sk.zPosition = -1
        parallaxFar.addChild(sk)

        // Mid layer: drifting dust motes and slow mist banks inside the dungeon
        parallaxMid.removeAllChildren(); parallaxMid.zPosition = -8
        let dust = SKEmitterNode()
        dust.particleTexture = Art.spark; dust.particleBirthRate = 30; dust.particleLifetime = 14
        dust.particlePositionRange = CGVector(dx: CGFloat(world.w) * T, dy: CGFloat(world.h) * T)
        dust.position = CGPoint(x: CGFloat(world.w) * T / 2, y: CGFloat(world.h) * T / 2)
        dust.particleSpeed = 8; dust.particleSpeedRange = 6; dust.emissionAngleRange = .pi * 2
        dust.particleScale = 0.18; dust.particleScaleRange = 0.12; dust.particleColor = theme.mist.blended(withFraction: 0.5, of: .white)!
        dust.particleColorBlendFactor = 1; dust.particleAlpha = 0.5; dust.particleAlphaRange = 0.3; dust.particleBlendMode = .add
        dust.advanceSimulationTime(14)
        dust.zPosition = 5
        worldNode.addChild(dust)
        for _ in 0..<14 {
            let fog = SKSpriteNode(texture: Art.softGlow, size: CGSize(width: CGFloat(rng.range(500, 900)), height: CGFloat(rng.range(140, 260))))
            fog.color = theme.mist; fog.colorBlendFactor = 1; fog.alpha = 0.10; fog.blendMode = .add
            fog.position = CGPoint(x: CGFloat(rng.int(world.w)) * T, y: CGFloat(rng.int(world.h)) * T); fog.zPosition = 6
            let dx = CGFloat(rng.range(120, 300))
            fog.run(.repeatForever(.sequence([.moveBy(x: dx, y: 0, duration: Double(rng.range(18, 30))), .moveBy(x: -dx, y: 0, duration: Double(rng.range(18, 30)))])))
            worldNode.addChild(fog)
        }
    }

    /// Torches: flame/ember/halo visuals everywhere, their light BAKED into the masonry (seamless, free),
    /// plus a 6-light pool that follows the camera to light characters dynamically.
    var torchSpots: [CGPoint] = []
    var lightPool: [SKLightNode] = []
    func addLighting() {
        let torchColor = SKColor(red: 1, green: 0.62, blue: 0.25, alpha: 1)
        for p in torchSpots {
            let t = Art.torch(light: torchColor); t.position = p; t.zPosition = -4
            worldNode.addChild(t)
        }
        lightPool = (0..<6).map { _ in
            let l = SKLightNode(); l.categoryBitMask = 1; l.lightColor = torchColor; l.falloff = 1.5
            l.ambientColor = .clear; worldNode.addChild(l); return l
        }
        let fill = SKLightNode(); fill.categoryBitMask = 1; fill.lightColor = .black
        fill.ambientColor = theme.mist.blended(withFraction: 0.55, of: .black)!; fill.falloff = 10
        worldNode.addChild(fill)
    }
    let playerLight = SKLightNode()

    func spawnBeing(_ s: Soul, at p: CGPoint, role: Being.Role) {
        var soul = s
        soul.metCount += 1
        let b = Being(soul: soul, pos: p, role: role)
        if chron.mutator == "Blood Moon" { b.maxHP *= 1.4; b.hp = b.maxHP }
        b.onWhoosh = { [weak self] in self?.synth?.sfxWhoosh = 0.7 }
        beings.append(b); worldNode.addChild(b.node)
        writeBack(b)
    }

    func writeBack(_ b: Being) {
        if let i = chron.souls.firstIndex(where: { $0.id == b.soul.id }) { chron.souls[i] = b.soul }
    }

    /// Keep the chronicle bounded: forget unremarkable strangers, but never those with history
    /// (grudges, debts, the dead whose kin may still come looking).
    func pruneSouls() {
        let cap = 240
        guard chron.souls.count > cap else { return }
        let avenged = Set(chron.souls.compactMap { $0.kinOf })
        var keep = chron.souls.filter { $0.grudge > 0 || $0.debt > 0 || $0.kinOf != nil || avenged.contains($0.id) || !$0.alive }
        if keep.count > cap { keep = Array(keep.suffix(cap)) }
        let rest = chron.souls.filter { s in !keep.contains { $0.id == s.id } }
        chron.souls = keep + rest.suffix(max(0, cap - keep.count))
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        if simFrozen { isPaused = true; return }
        let dt = lastTime == 0 ? 1.0 / 60 : min(1.0 / 30, currentTime - lastTime)
        lastTime = currentTime
        tick(CGFloat(dt))
        if GameScene.logFrames { NotificationCenter.default.post(name: NSNotification.Name("RiftbornFrame"), object: nil) }
    }
    static let logFrames = CommandLine.arguments.contains("--fpslog")

    func tick(_ dt: CGFloat) {
        Prof.time("tick total") { tickInner(dt) }
    }

    func tickInner(_ dt: CGFloat) {
        stats.frames += 1
        input.poll()
        if input.hit(.pause) { mode = (mode == .paused) ? .play : (mode == .play ? .paused : mode); refreshPanel() }
        // Capture attack presses (with their modifier) once per poll, even while hit-stop freezes play.
        // Any modal mode discards a pending buffer so it cannot fire on return.
        if let p = player { if mode == .play { p.captureAttack(input) } else { p.discardAttackBuffer() } }
        // Hit-stop: freeze simulation for a few frames on impact (sells weight; standard in AAA melee)
        if hitStop > 0 { hitStop -= Double(dt); combat.hitStopFrames += 1; updateCamera(dt); return }
        switch mode {
        case .play: play(dt)
        case .dialogue: dialogue()
        case .portal: portalChoice()
        case .dead: if input.hit(.jump) || input.hit(.opt1) { respawn() }
        case .paused: break
        }
        updateCamera(dt)
        updateHUD()
        for (i, t) in toast.enumerated().reversed() {
            toast[i].1 -= Double(dt)
            if t.1 <= 0 { t.0.removeFromParent(); toast.remove(at: i) }
        }
    }

    func updateCamera(_ dt: CGFloat) {
        // Frame like PoP: visible height ~480 world units so the hero is ~1/6 of the screen; clamped inside the level
        let zoom: CGFloat = 480 / max(400, size.height)
        let target = CGPoint(x: player.pos.x + player.facing * 70, y: player.pos.y + 60)
        camBase.x += (target.x - camBase.x) * min(1, 5 * dt)
        camBase.y += (target.y - camBase.y) * min(1, 5 * dt)
        let halfW = size.width * zoom / 2, halfH = size.height * zoom / 2
        let maxX = CGFloat(world.w) * T, maxY = CGFloat(world.h) * T
        camBase.x = clamp(camBase.x, halfW, max(halfW, maxX - halfW))
        camBase.y = clamp(camBase.y, halfH, max(halfH, maxY - halfH))
        // Directional, decaying shake (biased along the hit direction)
        shake *= 0.86; if shake < 0.2 { shake = 0 }
        let sx = shake > 0 ? vrand(-shake...shake) * 0.5 + shakeDir * shake * 0.6 : 0
        let sy = shake > 0 ? vrand(-shake...shake) * 0.6 : 0
        cam.position = CGPoint(x: camBase.x + sx * zoom, y: camBase.y + sy * zoom)
        cam.setScale(zoom * (1 + clamp(zoomPunch, -0.035, 0.035))); zoomPunch *= 0.88
        // Camera children already scale with the camera, so the HUD keeps a constant on-screen size as-is.
        hud.setScale(1); vignette.setScale(1); hurtOverlay.setScale(1)
        // Light pool: move the 6 real lights to the torches nearest the camera (SpriteKit caps lights per sprite at 8)
        if stats.frames % 8 == 0 && !torchSpots.isEmpty {
            let near = torchSpots.sorted { hypot($0.x - cam.position.x, $0.y - cam.position.y) < hypot($1.x - cam.position.x, $1.y - cam.position.y) }
            for (i, l) in lightPool.enumerated() { l.isEnabled = i < near.count; if i < near.count { l.position = near[i] } }
        }
        parallaxFar.setScale(1)
        parallaxFar.position = CGPoint(x: -cam.position.x * 0.05, y: -cam.position.y * 0.03)
    }

    /// One-stop impact juice. dir = which way the hit pushes (screen-x).
    func impact(at p: CGPoint, dir: CGFloat, stop: Double, shake s: CGFloat, color: SKColor, blood: Bool, heavy: Bool) {
        hitStop = max(hitStop, stop)
        shake = min(10, max(shake, s)); shakeDir = dir
        if heavy { zoomPunch = -0.035 }
        synth?.sfxHit = heavy ? 1.6 : 1
        // Slash flash
        let slash = SKSpriteNode(texture: Art.spark, size: CGSize(width: heavy ? 150 : 100, height: heavy ? 18 : 12))
        slash.position = p; slash.zRotation = vrand(-0.6...0.6); slash.blendMode = .add; slash.zPosition = 40
        worldNode.addChild(slash)
        slash.run(.sequence([.group([.scaleX(to: 1.6, duration: 0.12), .fadeOut(withDuration: 0.14)]), .removeFromParent()]))
        // Sparks + blood
        let e = SKEmitterNode()
        e.particleTexture = Art.spark; e.numParticlesToEmit = heavy ? 34 : 18; e.particleBirthRate = 3000
        e.particleLifetime = 0.45; e.particleLifetimeRange = 0.25
        e.emissionAngle = dir > 0 ? 0 : .pi; e.emissionAngleRange = 1.3; e.particleSpeed = heavy ? 420 : 300; e.particleSpeedRange = 160
        e.yAcceleration = -900; e.particleScale = 0.35; e.particleScaleRange = 0.2; e.particleScaleSpeed = -0.5
        e.particleColor = blood ? SKColor(red: 0.75, green: 0.02, blue: 0.05, alpha: 1) : color
        e.particleColorBlendFactor = 1; e.particleBlendMode = blood ? .alpha : .add
        e.position = p; e.zPosition = 39; worldNode.addChild(e)
        e.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
        if blood {
            let s2 = SKEmitterNode(); s2.particleTexture = Art.spark; s2.numParticlesToEmit = 10; s2.particleBirthRate = 3000
            s2.particleLifetime = 0.25; s2.particleSpeed = 200; s2.emissionAngle = e.emissionAngle; s2.emissionAngleRange = 0.8
            s2.particleColor = color; s2.particleColorBlendFactor = 1; s2.particleBlendMode = .add; s2.particleScale = 0.4; s2.position = p; s2.zPosition = 41
            worldNode.addChild(s2); s2.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))
        }
    }

    func play(_ dt0: CGFloat) {
        // Brief slow-mo after kills / perfect parries (time dilation, like Sands of Time's flourish)
        slowMoT = max(0, slowMoT - Double(dt0))
        let dt = slowMoT > 0 ? dt0 * 0.4 : dt0
        damageVignette *= 0.92; hurtOverlay.alpha = damageVignette * 0.55 + (player.hp / player.maxHP < 0.3 ? 0.12 + 0.06 * CGFloat(sin(Double(stats.frames) * 0.12)) : 0)
        playerLight.isEnabled = false
        slowTime = max(0, slowTime - Double(dt)); overcharge = max(0, overcharge - Double(dt))
        player.update(dt, world, input)
        player.rig.updateTrail(active: player.phase == .active, in: worldNode, color: overcharge > 0 ? .cyan : SKColor(red: 1, green: 0.95, blue: 0.8, alpha: 1))
        Prof.time("beings") { updateBeings(dt) }
    }

    func updateBeings(_ dt: CGFloat) {
        if player.standingOnSpike(world) && player.invuln == 0 { hurtPlayer(25, from: nil); player.vel.dy = 600 }
        if player.pos.y < -200 { hurtPlayer(999, from: nil) }

        if input.hit(.cycle) && !chron.powers.isEmpty { player.powerIndex = (player.powerIndex + 1) % chron.powers.count }
        if input.hit(.power) { castPower() }

        let edt = slowTime > 0 ? dt * 0.35 : dt
        var anyAggro = false
        let swing = player.swing
        let playerThreat = player.threatening
        for b in beings where !b.dead {
            var tgt: CGPoint? = nil
            if b.role == .hostile {
                let d = hypot(player.pos.x - b.pos.x, player.pos.y - b.pos.y)
                if d < 420 { tgt = player.pos; anyAggro = true }
                if let a = beings.filter({ $0.role == .ally && !$0.dead }).min(by: { dist($0, b) < dist($1, b) }), dist(a, b) < min(d, 300) { tgt = a.pos }
                if d < 260 && !b.talked { b.talked = true; barkAt(b, Mind.greet(b.soul, chron, &rng)) }
            } else if b.role == .ally {
                if let h = beings.filter({ $0.role == .hostile && !$0.dead }).min(by: { dist($0, b) < dist($1, b) }), dist(h, b) < 400 { tgt = h.pos }
                else if abs(player.pos.x - b.pos.x) > 120 { tgt = player.pos }
            }
            let facingMe = (player.pos.x - b.pos.x) * player.facing < 0
            let out = b.update(edt, world, target: tgt, playerPos: player.pos, threat: playerThreat && facingMe && abs(player.pos.x - b.pos.x) < 110, r: &rng)
            b.rig.updateTrail(active: b.phase == .active && b.soul.faction != .echoes, in: worldNode, color: b.tint)
            if let m = out.melee {
                if b.role == .hostile {
                    if m.intersects(player.rect) { hurtPlayer(CGFloat(6 + b.soul.level * 3), from: b) }
                    for a in beings where a.role == .ally && !a.dead && m.intersects(a.rect) { damage(a, 8, by: b, dir: b.facing, spec: .light1) }
                } else if b.role == .ally {
                    for h in beings where h.role == .hostile && !h.dead && m.intersects(h.rect) && h !== b { damage(h, CGFloat(8 + b.soul.level * 2), by: nil, dir: b.facing, spec: .light1) }
                }
            }
            if let v = out.bolt {
                let bolt = Bolt(pos: CGPoint(x: b.pos.x, y: b.pos.y + 34), vel: v, friendly: b.role == .ally, dmg: CGFloat(8 + b.soul.level * 3),
                                color: b.role == .ally ? .green : SKColor(red: 1, green: 0.8, blue: 0.25, alpha: 1))
                bolts.append(bolt); worldNode.addChild(bolt.node); synth?.sfxZap = 1
            }
            // Player blade: one hit per target per swing
            if let s = swing, b.role == .hostile, s.intersects(b.rect), b.lastHitSwing != player.swingId {
                b.lastHitSwing = player.swingId
                let hitPoint = CGPoint(x: b.pos.x - player.facing * 6, y: b.pos.y + b.size.height * 0.6)
                let guarded = b.blocking && (b.pos.x - player.pos.x) * b.facing < 0
                let baseDmg = CGFloat(chron.power) * player.swingDamage * (overcharge > 0 ? 2 : 1) * (b.stun > 0 ? 1.5 : 1)
                if guarded && player.spec.breaksGuard {
                    // Guard break: block shattered, single stagger, reduced damage. Not a parry.
                    b.breakGuard(dir: player.facing); combat.guardBreaks += 1; combat.hits += 1
                    synth?.sfxClang = 1.3
                    damage(b, baseDmg * 0.65, by: nil, dir: player.facing, spec: player.spec)
                } else if guarded {
                    // PoP blockedstrike: steel on steel, attacker recoils, defender may riposte
                    b.blockedHit(); player.recoil(); combat.blockedByFoe += 1
                    impact(at: hitPoint, dir: player.facing, stop: 0.07, shake: 5, color: SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 1), blood: false, heavy: false)
                    synth?.sfxClang = 1
                } else {
                    b.hitReact(knock: player.spec.knock * (b.soul.faction == .wardens ? 0.6 : 1), dir: player.facing, high: player.attackKind == .overhead)
                    combat.hits += 1
                    damage(b, baseDmg, by: nil, dir: player.facing, spec: player.spec)
                }
            }
            if b.role == .fleeing && hypot(player.pos.x - b.pos.x, player.pos.y - b.pos.y) > 700 { b.dead = true; b.node.removeFromParent() }
            if b.standingOnSpike(world) && b.soul.faction != .hive { damage(b, 2, by: nil, dir: 0, spec: nil) }
        }
        updateCorpses(dt)
        beings.removeAll { $0.dead && $0.node.parent == nil }

        updateBolts(dt)
        synth?.targetIntensity = anyAggro ? 1 : (chron.mutator == "Maddening Depths" ? 0.35 : 0)

        // Interact: talk to the nearest being in range, shrine, chest, portal
        let near = beings.filter { !$0.dead && $0.role != .fleeing && hypot($0.pos.x - player.pos.x, $0.pos.y - player.pos.y) < 90 }
            .min { dist($0, player) < dist($1, player) }
        hint.text = ""
        if let n = near {
            hint.text = n.role == .hostile && n.hp / n.maxHP < 0.35 ? "[E] \(n.soul.name) is broken. Decide their fate." : "[E] Speak with \(n.soul.name)"
            if input.hit(.talk) { openDialogue(n) }
        }
        for i in props.indices where !props[i].used {
            if hypot(props[i].node.position.x - player.pos.x, props[i].node.position.y - player.pos.y - 20) < 50 {
                if props[i].kind == .shrine { hint.text = "[E] Commune with the shrine"; if input.hit(.talk) { useShrine(i) } }
                else { openChest(i) }
            }
        }
        if hypot(portalNode.position.x - player.pos.x, portalNode.position.y - player.pos.y - 30) < 60 { openPortal() }
    }

    func dist(_ a: Body, _ b: Body) -> CGFloat { hypot(a.pos.x - b.pos.x, a.pos.y - b.pos.y) }

    func updateBolts(_ dt: CGFloat) {
        for b in bolts {
            b.life -= Double(dt)
            b.pos.x += b.vel.dx * dt; b.pos.y += b.vel.dy * dt; b.node.position = b.pos
            if world.solidAt(b.pos) { b.life = 0 }
            if b.friendly {
                for h in beings where h.role == .hostile && !h.dead && h.rect.contains(b.pos) { damage(h, b.dmg, by: nil, dir: b.vel.dx > 0 ? 1 : -1, spec: .light1); b.life = 0 }
            } else if player.rect.insetBy(dx: -4, dy: -4).contains(b.pos) {
                if player.blocking { b.vel.dx *= -1.4; b.vel.dy *= -1; flash("Reflected"); b.life = 2; bolts.append(Bolt(pos: b.pos, vel: b.vel, friendly: true, dmg: b.dmg * 1.5, color: .cyan)); worldNode.addChild(bolts.last!.node); b.life = 0 }
                else { hurtPlayer(b.dmg, from: nil); b.life = 0 }
            }
        }
        for b in bolts where b.life <= 0 { b.node.removeFromParent() }
        bolts.removeAll { $0.life <= 0 }
    }

    // MARK: Combat outcomes

    func damage(_ b: Being, _ amt: CGFloat, by attacker: Being?, dir: CGFloat, spec: AttackSpec?) {
        b.hp -= amt
        let p = CGPoint(x: b.pos.x, y: b.pos.y + b.size.height * 0.6)
        if let s = spec { impact(at: p, dir: dir, stop: s.hitStop, shake: s.shake, color: b.tint, blood: b.soul.faction != .echoes, heavy: s.damage >= 2) }
        else { synth?.sfxHit = 0.6; b.flashT = 0.06 }
        let dmgLabel = label("\(Int(amt.rounded()))", size: spec.map { $0.damage >= 2 ? 22 : 15 } ?? 12, color: spec.map { $0.damage >= 2 ? SKColor(red: 1, green: 0.8, blue: 0.2, alpha: 1) : .white } ?? .gray, bold: true)
        dmgLabel.position = CGPoint(x: p.x, y: p.y + 20); dmgLabel.zPosition = 60; worldNode.addChild(dmgLabel)
        dmgLabel.run(.sequence([.group([.moveBy(x: dir * 20, y: 40, duration: 0.5), .sequence([.scale(to: 1.4, duration: 0.06), .scale(to: 1, duration: 0.1)]), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        if b.hp <= 0 { kill(b) }
    }

    func kill(_ b: Being) {
        guard !b.dead else { return }            // consequences are awarded exactly once
        b.dead = true; b.deathT = 0; stats.kills += 1
        barkAt(b, Mind.deathLine(b.soul, &rng))
        b.soul.alive = false
        writeBack(b)
        if b.role == .hostile {
            chron.cruelty += b.soul.motive == .fear ? 2 : 0
            chron.shift(b.soul.faction, -1)
            chron.note("\(b.soul.name) of \(b.soul.faction.rawValue) fell. (\(b.soul.motive.rawValue))")
            let mult = chron.mutator == "Blood Moon" ? 2 : 1
            gainXP((10 + b.soul.level * 5) * mult)
            chron.shards += rng.range(1, 3) * mult
        } else {
            chron.note("\(b.soul.name), who walked beside you, fell.")
        }
        synth?.sfxDeath = 1
        hitStop = max(hitStop, 0.10); zoomPunch = -0.035; slowMoT = max(slowMoT, 0.25)
        // Corpse lifetime is driven by `updateCorpses` in gameplay time (fade 1.1 s -> removal 1.9 s).
    }

    static let corpseCap = 8
    /// Separate pass for the dead: collapse/settle animation and timed removal. Never runs AI or melee.
    func updateCorpses(_ dt: CGFloat) {
        let corpses = beings.filter { $0.dead && $0.node.parent != nil }
        if corpses.count > GameScene.corpseCap {
            for c in corpses.sorted(by: { $0.deathT > $1.deathT }).prefix(corpses.count - GameScene.corpseCap) { c.node.removeFromParent() }
        }
        for c in corpses where c.node.parent != nil {
            c.updateDeath(dt, world)
            if c.deathT > 1.1 { c.node.alpha = CGFloat(max(0, 1 - (c.deathT - 1.1) / 0.8)) }
            if c.deathT >= 1.9 { c.node.removeFromParent() }
        }
    }

    func hurtPlayer(_ amt: CGFloat, from b: Being?) {
        guard player.invuln == 0 else { return }
        let dir: CGFloat = b.map { $0.pos.x < player.pos.x ? 1 : -1 } ?? -player.facing
        let hp = CGPoint(x: player.pos.x, y: player.pos.y + 34)
        if player.blocking && (b == nil || (b!.pos.x - player.pos.x) * player.facing > 0) {
            if player.parryWindow > 0, let b = b {
                // Perfect parry: attacker staggers, time slows, riposte window opens
                b.parried(); player.parryWindow = 0; combat.parries += 1
                impact(at: hp, dir: -dir, stop: 0.085, shake: 9, color: .cyan, blood: false, heavy: true)
                synth?.sfxClang = 1.5; slowMoT = 0.5
                flash("PARRY"); return
            }
            player.hp -= amt * 0.2; player.energy -= 12; player.vel.dx = dir * 180; combat.playerBlocks += 1
            impact(at: hp, dir: dir, stop: 0.05, shake: 4, color: SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 1), blood: false, heavy: false)
            synth?.sfxClang = 1
        } else {
            player.hp -= amt; player.hurtFlash = 0.12; player.hurtPose = 0.25; player.invuln = 0.5
            player.phase = .none
            player.cancelTraversal(); player.discardAttackBuffer()
            player.vel.dx = dir * 340; player.vel.dy = 320
            impact(at: hp, dir: dir, stop: 0.09, shake: 11, color: .red, blood: true, heavy: false)
            damageVignette = 1
        }
        if player.hp <= 0 { die(killer: b) }
    }

    func die(killer: Being?) {
        mode = .dead; chron.deaths += 1
        player.cancelTraversal(); player.discardAttackBuffer()
        let lost = chron.shards / 2; chron.shards -= lost
        var line = "You fell in \(theme.name).\nLost \(lost) shards."
        if let k = killer {
            k.soul.grudge += 1; k.soul.level += 1      // Nemesis: your killer grows
            writeBack(k)
            line += "\n\n\(k.soul.name) grows stronger from your death.\nThey will remember this."
            chron.note("\(k.soul.name) slew the rift-walker and rose to level \(k.soul.level).")
        }
        saveChronicle()
        showPanel(line + "\n\n[Space] Rise again")
    }

    func respawn() {
        panel.isHidden = true; mode = .play
        buildDepth()
    }

    func gainXP(_ n: Int) {
        chron.xp += n
        while chron.xp >= chron.level * 60 {
            chron.xp -= chron.level * 60; chron.level += 1
            chron.maxHP += 12; chron.power += 3
            player.maxHP = CGFloat(chron.maxHP); player.hp = player.maxHP
            flash("ASCENDED: Level \(chron.level)")
        }
    }

    func castPower() {
        guard player.moveMode == .free else { return }     // no powers while hanging/climbing
        guard !chron.powers.isEmpty else { flash("No powers. Find a shrine."); return }
        let p = chron.powers[player.powerIndex % chron.powers.count]
        let cost: CGFloat = p == "Blink" ? 20 : 40
        guard player.energy >= cost else { flash("Not enough energy"); return }
        player.energy -= cost; synth?.sfxZap = 1
        switch p {
        case "Psi Storm":
            let c = CGPoint(x: player.pos.x + player.facing * 120, y: player.pos.y)
            let ring = SKShapeNode(circleOfRadius: 130); ring.position = CGPoint(x: c.x, y: c.y + 30)
            ring.strokeColor = .cyan; ring.glowWidth = 14; ring.fillColor = SKColor(red: 0.3, green: 0.6, blue: 1, alpha: 0.25)
            worldNode.addChild(ring); ring.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
            for b in beings where b.role == .hostile && !b.dead && hypot(b.pos.x - c.x, b.pos.y - c.y) < 140 { damage(b, CGFloat(chron.power) * 2.5, by: nil, dir: b.pos.x > c.x ? 1 : -1, spec: .heavy) }
            shake = 12
        case "Blink":
            var nx = player.pos.x
            for _ in 0..<8 { let t = nx + player.facing * 24; if world.at(Int(t / T), Int((player.pos.y + 20) / T)) == .solid { break }; nx = t }
            spark(at: player.pos, color: .cyan); player.pos.x = nx; player.invuln = 0.3
        case "Chrono Slow": slowTime = chron.mutator == "Shattered Time" ? 9 : 5; flash("Time bends")
        case "Swarm Spawn":
            for _ in 0..<2 {
                var s = Soul(id: -1, name: "Broodling", faction: .hive, motive: .duty, backstory: "...")
                s.level = chron.level
                let b = Being(soul: s, pos: CGPoint(x: player.pos.x - player.facing * 30, y: player.pos.y + 10), role: .ally)
                b.maxHP = 30; b.hp = 30
                beings.append(b); worldNode.addChild(b.node)
                b.node.run(.sequence([.wait(forDuration: 15), .run { b.dead = true }, .removeFromParent()]))
            }
        case "Overcharge": overcharge = 6; flash("OVERCHARGE")
        default: break
        }
    }

    // MARK: Dialogue

    func openDialogue(_ b: Being) {
        talkingTo = b; mode = .dialogue; stats.talks += 1
        b.soul.metCount += 1
        let broken = b.role == .hostile && b.hp / b.maxHP < 0.35
        var text = "\(b.soul.name)  -  \(b.soul.faction.rawValue), driven by \(b.soul.motive.rawValue)\n\n"
        if broken {
            text += "\"\(Mind.deathLine(b.soul, &rng).replacingOccurrences(of: "...", with: ","))\"  They can barely stand."
            dialogueOptions = ["Spare them", "End them"]
        } else if b.role == .ally {
            text += "\"\(rng.pick(["I go where you go.", "The rift is quieter with you in it.", "Ask, and I'll answer."]))\""
            dialogueOptions = ["Ask about their past", "Release them from your service"]
        } else {
            text += "\"\(Mind.greet(b.soul, chron, &rng))\""
            let c = Mind.choices(b.soul); dialogueOptions = [c.0, c.1]
        }
        text += "\n\n[1] \(dialogueOptions[0])     [2] \(dialogueOptions[1])"
        showPanel(text)
    }

    func dialogue() {
        guard let b = talkingTo else { mode = .play; return }
        var pick = -1
        if input.hit(.opt1) { pick = 0 } else if input.hit(.opt2) { pick = 1 }
        guard pick >= 0 else { return }
        let broken = b.role == .hostile && b.hp / b.maxHP < 0.35
        var reply = ""
        if broken {
            if pick == 0 {
                b.soul.debt += 1; b.soul.grudge = max(0, b.soul.grudge - 1); b.role = .fleeing
                chron.mercy += 1; chron.shift(b.soul.faction, 2); stats.spared += 1
                chron.note("You spared \(b.soul.name). They owe you.")
                reply = "\"...I won't forget this.\"  \(b.soul.name) limps into the dark."
            } else {
                chron.cruelty += 1; reply = "\"So this is what you are.\""; kill(b)
            }
        } else if b.role == .ally {
            if pick == 0 { reply = "\"\(b.soul.backstory)\"" }
            else { b.role = .wanderer; reply = "\"Then our paths split here. For now.\"" }
        } else {
            var s = b.soul
            let (line, ally, hostile) = Mind.resolve(&s, choice: pick, &chron, &rng)
            b.soul = s
            reply = "\"\(line)\""
            if ally { b.role = .ally; reply += "\n\n\(b.soul.name) joins you." }
            else if hostile { b.role = .hostile; b.talked = true }
            else if b.role == .hostile { b.role = .fleeing }
        }
        b.restyle(); writeBack(b); saveChronicle()
        showPanel(reply)
        mode = .play; talkingTo = nil
        panel.run(.sequence([.wait(forDuration: 3.0), .hide()]))
    }

    // MARK: Props, portal

    func useShrine(_ i: Int) {
        props[i].used = true; props[i].node.removeAllActions(); props[i].node.alpha = 0.25
        let unknown = Mind.allPowers.filter { !chron.powers.contains($0) }
        if let p = unknown.first(where: { _ in true }).map({ _ in unknown[rng.int(unknown.count)] }) {
            chron.powers.append(p); flash("Learned: \(p)  [Q] cast  [R] cycle")
        } else { chron.power += 4; flash("The shrine sharpens your blade (+4 power)") }
        player.hp = player.maxHP; saveChronicle()
    }

    func openChest(_ i: Int) {
        props[i].used = true; props[i].node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        let n = rng.range(2, 6) + chron.depth
        chron.shards += n; flash("+\(n) shards")
        if rng.chance(0.3) { chron.maxHP += 5; player.maxHP += 5; flash("Vitality +5") }
    }

    let mutators: [(String, String)] = [
        ("Blood Moon", "Enemies are tougher. Rewards doubled."),
        ("Hive Ascendant", "The Hive floods the depths."),
        ("Echoing Silence", "Fewer foes. More wanderers with secrets."),
        ("Shattered Time", "Time bends: Chrono Slow lasts longer."),
        ("Pilgrim's Road", "Shrines appear more often."),
        ("Warden's Oath", "Wardens are drawn to your banner."),
        ("Maddening Depths", "Everything is deeper, darker, louder.")
    ]

    func openPortal() {
        mode = .portal; synth?.sfxPortal = 1
        var pool = mutators; portalOptions = []
        for _ in 0..<3 { let i = rng.int(pool.count); portalOptions.append(pool.remove(at: i)) }
        var text = "THE RIFT ASKS WHAT YOU WANT TO BECOME\n\n\(Mind.portalProphecy(chron))\n\n"
        for (i, o) in portalOptions.enumerated() { text += "[\(i + 1)] \(o.0): \(o.1)\n" }
        showPanel(text)
    }

    func portalChoice() {
        var pick = -1
        if input.hit(.opt1) { pick = 0 } else if input.hit(.opt2) { pick = 1 } else if input.hit(.opt3) { pick = 2 }
        guard pick >= 0 else { return }
        chron.mutator = portalOptions[pick].0
        chron.choicesAtPortal.append(chron.mutator)
        chron.depth += 1; stats.portals += 1
        chron.note("Entered depth \(chron.depth) under \(chron.mutator).")
        panel.isHidden = true; mode = .play
        buildDepth()
    }

    // MARK: Presentation

    func showPanel(_ t: String) { panelText.text = t; panel.isHidden = false; panel.removeAllActions() }
    func refreshPanel() {
        if mode == .paused {
            let recent = chron.log.suffix(8).joined(separator: "\n")
            showPanel("PAUSED  -  Chronicle of \(chron.alignment)\n\n\(recent.isEmpty ? "Nothing yet." : recent)\n\n[Esc] resume")
        } else if mode == .play { panel.isHidden = true }
    }

    func barkAt(_ b: Being, _ text: String) {
        let l = label(text, size: 11, color: SKColor(white: 1, alpha: 0.95))
        l.position = CGPoint(x: b.pos.x, y: b.pos.y + b.size.height + 34); l.zPosition = 50
        worldNode.addChild(l)
        l.run(.sequence([.wait(forDuration: 3.5), .fadeOut(withDuration: 0.8), .removeFromParent()]))
    }

    func flash(_ t: String) {
        let l = label(t, size: 16, color: theme?.edge ?? .white, bold: true)
        l.position = CGPoint(x: 0, y: 80 - CGFloat(toast.count) * 22); hud.addChild(l)
        toast.append((l, 2.0))
    }
    func say(_ t: String) { flash(t) }

    func spark(at p: CGPoint, color: SKColor) {
        for _ in 0..<6 {
            let s = SKSpriteNode(color: color, size: CGSize(width: 4, height: 4))
            s.position = p; s.zPosition = 20; worldNode.addChild(s)
            s.run(.sequence([.group([.moveBy(x: vrand(-40...40), y: vrand(-10...50), duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
    }

    func updateHUD() {
        hpBar.xScale = max(0, player.hp / player.maxHP)
        enBar.xScale = max(0, player.energy / 100)
        info.text = "Lv \(chron.level)   Power \(chron.power)   Shards \(chron.shards)   \(chron.alignment)  (\(chron.mercy) mercy / \(chron.cruelty) cruelty)"
        let rep = Faction.allCases.map { "\($0.rawValue.replacingOccurrences(of: "The ", with: "")) \(chron.repOf($0) >= 0 ? "+" : "")\(chron.repOf($0))" }.joined(separator: "  ")
        let pw = chron.powers.isEmpty ? "No powers" : chron.powers[player.powerIndex % chron.powers.count]
        powerLabel.text = "\(pw)   |   \(rep)"
        if mode == .play && hint.text == "" && stats.frames < 60 * 40 { hint.text = "A/D move  Space jump  hold into wall: wall-run  J strike (x3 combo)  K dash  L block (tap = parry)  E talk  Q power  Esc chronicle" }
        hud.childNode(withName: "hintPlate")?.isHidden = (hint.text ?? "").isEmpty
    }
}

extension Array {
    func shuffledWith(_ r: inout RNG) -> [Element] {
        var a = self
        if a.count < 2 { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, r.int(i + 1)) }
        return a
    }
}
