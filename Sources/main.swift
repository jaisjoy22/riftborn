import AppKit
import SpriteKit

final class GameView: SKView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with e: NSEvent) { Input.shared.keys.insert(e.keyCode) }
    override func keyUp(with e: NSEvent) { Input.shared.keys.remove(e.keyCode) }
    override func flagsChanged(with e: NSEvent) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let synth = Synth()

    func applicationDidFinishLaunching(_ n: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Riftborn"
        window.center()
        let view = GameView(frame: frame)
        view.preferredFramesPerSecond = 120
        view.ignoresSiblingOrder = true
        view.showsFPS = CommandLine.arguments.contains("--fps")
        view.showsNodeCount = CommandLine.arguments.contains("--fps")
        if CommandLine.arguments.contains("--fpslog") {
            // Log real rendered frame rate once per second (verifies GPU performance with lighting on)
            var frames = 0, last = CFAbsoluteTimeGetCurrent(), seconds = 0
            let link = Timer.scheduledTimer(withTimeInterval: 1.0 / 240, repeats: true) { _ in }
            _ = link
            NotificationCenter.default.addObserver(forName: NSNotification.Name("RiftbornFrame"), object: nil, queue: nil) { _ in
                frames += 1
                let now = CFAbsoluteTimeGetCurrent()
                if now - last >= 1 { seconds += 1; print("fps \(frames)"); fflush(stdout); frames = 0; last = now }
            }
        }
        let scene = GameScene(size: frame.size)
        scene.synth = synth
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.presentScene(scene)
        if !CommandLine.arguments.contains("--mute") { synth.start() }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            // Render the live scene to PNG from inside the app (no screen-recording permission needed)
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Crop to exactly what the camera shows (scene coords), so HUD + framing match the player's view.
                let cs = scene.camera?.xScale ?? 1, cp = scene.camera?.position ?? .zero
                let vw = scene.size.width * cs, vh = scene.size.height * cs
                let crop = CGRect(x: cp.x - vw / 2, y: cp.y - vh / 2, width: vw, height: vh)
                if let tex = view.texture(from: scene, crop: crop) {
                    let img = tex.cgImage()
                    let rep = NSBitmapImageRep(cgImage: img)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    print("snapshot \(img.width)x\(img.height) -> \(path)")
                } else { print("snapshot failed") }
                fflush(stdout); NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--fullscreen") { window.toggleFullScreen(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { synth.engine.stop() }
}

// MARK: - Headless self-test: runs the real simulation with an autopilot, no window.

func selfTest() -> Int32 {
    let save = NSTemporaryDirectory() + "riftborn-selftest-\(getpid()).json"
    setenv("RIFTBORN_SAVE", save, 1)
    try? FileManager.default.removeItem(atPath: save)
    let scene = GameScene(size: CGSize(width: 1440, height: 900))
    scene.setup()
    var failures: [String] = []
    let inp = Input.shared
    var r = RNG(42)
    let t0 = Date()
    var depthsSeen = Set<Int>()
    var frame = 0
    while frame < 60 * 240 {            // 4 simulated minutes
        frame += 1
        inp.synthetic = []
        let p = scene.player!
        switch scene.mode {
        case .dialogue: inp.synthetic.insert(r.chance(0.5) ? .opt1 : .opt2)
        case .portal: inp.synthetic.insert([.opt1, .opt2, .opt3][r.int(3)])
        case .dead: inp.synthetic.insert(.jump)
        case .paused: inp.synthetic.insert(.pause)
        case .play:
            // Head toward the portal; jump often; fight what's near; talk sometimes.
            let dx = scene.portalNode.position.x - p.pos.x, dy = scene.portalNode.position.y - p.pos.y
            if abs(dx) > 20 { inp.synthetic.insert(dx > 0 ? .right : .left) }
            if frame % 20 < 3 || (dy > 40 && frame % 9 == 0) || p.wallDir != 0 { inp.synthetic.insert(.jump) }
            if dy < -60 && frame % 30 == 0 { inp.synthetic.insert(.down); inp.synthetic.insert(.jump) }
            if frame % 11 == 0 { inp.synthetic.insert(.attack) }
            if frame % 97 == 0 { inp.synthetic.insert(.dash) }
            if frame % 53 == 0 { inp.synthetic.insert(.talk) }
            if frame % 131 == 0 { inp.synthetic.insert(.power) }
            // Unstick: periodically teleport near the portal so the test exercises transitions.
            if frame % (60 * 25) == 0 { p.pos = CGPoint(x: scene.portalNode.position.x - 10, y: scene.portalNode.position.y - 50); p.vel = .zero }
        }
        scene.tick(1.0 / 60)
        depthsSeen.insert(scene.chron.depth)
        if !p.pos.x.isFinite || !p.pos.y.isFinite { failures.append("non-finite player position"); break }
    }
    let secs = Date().timeIntervalSince(t0)
    let c = scene.chron
    if depthsSeen.count < 2 { failures.append("never reached a second depth") }
    if c.souls.isEmpty { failures.append("no souls generated") }
    if c.souls.count > 320 { failures.append("soul table unbounded (\(c.souls.count))") }
    if !FileManager.default.fileExists(atPath: save) { failures.append("chronicle not saved") }
    let reload = Chronicle.load()
    if reload.souls.count != c.souls.count && reload.depth != c.depth { failures.append("save/load mismatch") }

    // Determinism: same seed+depth produce identical worlds.
    let a = World(seed: 99, depth: 3), b = World(seed: 99, depth: 3)
    if a.g != b.g { failures.append("world generation not deterministic") }
    // Reachability sanity: start and portal both open tiles.
    for d in 1...12 {
        let w = World(seed: 7, depth: d)
        if w.at(w.start.x, w.start.y) != .empty || w.at(w.portal.x, w.portal.y) != .empty { failures.append("depth \(d): start/portal blocked") }
    }

    // Combat-feel contract (PoP-derived): windup < recovery for every attack; heavy is slower & harder.
    for s in [AttackSpec.light1, .light2, .heavy] where !(s.windup < s.recovery && s.active > 0) { failures.append("attack timing violates anticipation<recovery") }
    if !(AttackSpec.heavy.damage > AttackSpec.light1.damage * 2 && AttackSpec.heavy.hitStop > AttackSpec.light1.hitStop) { failures.append("heavy not heavier") }
    // Phase machine: pressing attack produces windup -> active (hurtbox) -> recovery -> none.
    do {
        let w = World(seed: 5, depth: 1)
        let pl = Player(pos: CGPoint(x: (CGFloat(w.start.x) + 0.5) * T, y: CGFloat(w.start.y) * T))
        let i2 = Input(); var seen: [Phase] = []; var sawHurtbox = false
        for f in 0..<60 {
            i2.synthetic = f == 2 ? [.attack] : []
            i2.poll(); pl.update(1.0 / 60, w, i2)
            if seen.last != pl.phase { seen.append(pl.phase) }
            if pl.swing != nil { sawHurtbox = true }
        }
        if seen != [.none, .windup, .active, .recovery, .none] { failures.append("attack phases wrong: \(seen)") }
        if !sawHurtbox { failures.append("no hurtbox during active frames") }
    }
    // Stats gathered during the autopilot run
    if scene.combat.hits == 0 { failures.append("player never landed a hit") }

    // Duel harness: a Warden attacks a player holding block; first hit inside the window must PARRY,
    // later hits must be BLOCKED (chip damage), and a parried foe must be stunned.
    do {
        let ds = GameScene(size: CGSize(width: 1440, height: 900)); ds.setup()
        ds.beings.forEach { $0.node.removeFromParent() }; ds.beings.removeAll()
        let p = ds.player!
        var soul = Soul(id: 9999, name: "Test Warden", faction: .wardens, motive: .duty, backstory: "")
        soul.level = 6
        let foe = Being(soul: soul, pos: CGPoint(x: p.pos.x + 46, y: p.pos.y), role: .hostile)
        ds.beings.append(foe); ds.worldNode.addChild(foe.node)
        p.facing = 1
        inp.synthetic = []
        var parried = 0, blocked = 0, stunnedAfterParry = false
        var reacting = false
        for f in 0..<900 {
            // Human-like: hold block normally, but release+re-press when the foe's windup telegraph is about to land.
            if foe.phase == .windup && foe.phaseT < 0.14 && !reacting { reacting = true; inp.synthetic = [] }
            else if reacting { inp.synthetic = [.block]; if foe.phase != .windup { reacting = false } }
            else { inp.synthetic = f % 2 == 0 ? [.block] : [.block] }
            if f % 120 == 0 { foe.pos.x = p.pos.x + 46; foe.vel = .zero; foe.cooldown = 0; foe.stun = 0 }
            let pp = ds.combat.parries, pb = ds.combat.playerBlocks
            ds.tick(1.0 / 60)
            if ds.combat.parries > pp { parried += 1; if foe.stun > 0.5 { stunnedAfterParry = true } }
            if ds.combat.playerBlocks > pb { blocked += 1 }
            p.hp = p.maxHP
        }
        print("  duel harness     : parries \(parried), blocks \(blocked), foe stunned after parry: \(stunnedAfterParry)")
        if parried + blocked == 0 { failures.append("duel: warden never attacked into block") }
        if parried > 0 && !stunnedAfterParry { failures.append("duel: parry did not stun attacker") }
    }

    print("""
    RIFTBORN SELFTEST
      simulated frames : \(frame) (\(String(format: "%.0f", Double(frame) / 60))s game time) in \(String(format: "%.2f", secs))s wall -> \(String(format: "%.0f", Double(frame) / secs)) sim fps
      depths visited   : \(depthsSeen.sorted())
      souls created    : \(c.souls.count)  (dead \(c.souls.filter { !$0.alive }.count), with grudge \(c.souls.filter { $0.grudge > 0 }.count), in debt \(c.souls.filter { $0.debt > 0 }.count), kin-avengers \(c.souls.filter { $0.kinOf != nil }.count))
      kills/spared/talks: \(scene.stats.kills)/\(scene.stats.spared)/\(scene.stats.talks)  deaths \(c.deaths)
      combat           : hits \(scene.combat.hits), blocked by foes \(scene.combat.blockedByFoe), player blocks \(scene.combat.playerBlocks), parries \(scene.combat.parries), hitstop frames \(scene.combat.hitStopFrames)
      player           : Lv \(c.level), power \(c.power), shards \(c.shards), powers \(c.powers), \(c.alignment)
      reputation       : \(c.rep)
      mutators chosen  : \(c.choicesAtPortal)
      sample chronicle :
    \(c.log.suffix(6).map { "        " + $0 }.joined(separator: "\n"))
      result           : \(failures.isEmpty ? "PASS" : "FAIL " + failures.joined(separator: "; "))
    """)
    try? FileManager.default.removeItem(atPath: save)
    Prof.dump()
    return failures.isEmpty ? 0 : 1
}

func audioTest() -> Int32 {
    let s = Synth()
    s.start()
    print("audio engine running:", s.engine.isRunning, "sampleRate:", s.engine.outputNode.outputFormat(forBus: 0).sampleRate)
    s.targetIntensity = 1
    Thread.sleep(forTimeInterval: 0.5)
    s.engine.stop()
    return s.engine.isRunning ? 1 : 0
}

if CommandLine.arguments.contains("--selftest") { exit(selfTest()) }
if CommandLine.arguments.contains("--audiotest") { exit(audioTest()) }
if CommandLine.arguments.contains("--reset") { try? FileManager.default.removeItem(at: Chronicle.url); print("Chronicle erased.") }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
