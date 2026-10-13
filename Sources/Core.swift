import SpriteKit
import GameController

let T: CGFloat = 32          // tile size in points
let GRAVITY: CGFloat = -2200

// Deterministic xorshift RNG so every rift is reproducible from its seed.
struct RNG {
    var s: UInt64
    init(_ seed: UInt64) { s = (seed &* 6364136223846793005) &+ 0x9E3779B97F4A7C15; if s == 0 { s = 1 } }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
    mutating func range(_ a: Int, _ b: Int) -> Int { a + int(b - a + 1) }
    mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000.0 }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func pick<E>(_ a: [E]) -> E { a[int(a.count)] }
}

enum Act: Hashable { case left, right, up, down, jump, attack, dash, block, talk, power, opt1, opt2, opt3, cycle, pause, careful }

final class Input {
    static let shared = Input()
    var keys = Set<UInt16>()
    var synthetic = Set<Act>()          // used by --selftest autopilot
    var suppressHardware = false        // test fixtures: ignore keyboard + controllers entirely
    /// Plan-v3 spelling of `suppressHardware` (same storage).
    var suppressesHardware: Bool { get { suppressHardware } set { suppressHardware = newValue } }
    private var now = Set<Act>(), prev = Set<Act>()

    func poll() {
        prev = now
        var s = synthetic
        if suppressHardware { now = s; return }
        func k(_ codes: UInt16...) -> Bool { codes.contains { keys.contains($0) } }
        if k(0, 123) { s.insert(.left) }
        if k(2, 124) { s.insert(.right) }
        if k(13, 126) { s.insert(.up) }
        if k(1, 125) { s.insert(.down) }
        if k(49, 13, 126) { s.insert(.jump) }
        if k(38) { s.insert(.attack) }
        if k(40) { s.insert(.dash) }
        if k(37) { s.insert(.block) }
        if k(14) { s.insert(.talk) }
        if k(12) { s.insert(.power) }
        if k(18) { s.insert(.opt1) }
        if k(19) { s.insert(.opt2) }
        if k(53) { s.insert(.pause) }
        if k(15) { s.insert(.cycle) }
        if k(20) { s.insert(.opt3) }
        if k(56, 60) { s.insert(.careful) }         // left/right Shift (fed by flagsChanged)
        if let g = GCController.current?.extendedGamepad {
            let x = g.leftThumbstick.xAxis.value, y = g.leftThumbstick.yAxis.value
            if x < -0.4 || g.dpad.left.isPressed { s.insert(.left) }
            if x > 0.4 || g.dpad.right.isPressed { s.insert(.right) }
            if y > 0.5 || g.dpad.up.isPressed { s.insert(.up) }
            if y < -0.5 || g.dpad.down.isPressed { s.insert(.down) }
            if g.buttonA.isPressed { s.insert(.jump) }
            if g.buttonX.isPressed { s.insert(.attack) }
            if g.rightShoulder.isPressed { s.insert(.dash); s.insert(.opt2) }
            if g.leftShoulder.isPressed { s.insert(.block); s.insert(.opt1) }
            if g.buttonY.isPressed { s.insert(.talk) }
            if g.buttonB.isPressed { s.insert(.power) }
            if g.buttonMenu.isPressed { s.insert(.pause) }
            if g.rightTrigger.isPressed { s.insert(.cycle) }
            if g.leftTrigger.isPressed { s.insert(.opt3); s.insert(.careful) }   // opt3 in menus, careful in play
        }
        now = s
    }
    func held(_ a: Act) -> Bool { now.contains(a) }
    func hit(_ a: Act) -> Bool { now.contains(a) && !prev.contains(a) }
}

struct Theme {
    let name: String
    let sky: SKColor, rock: SKColor, edge: SKColor, mist: SKColor
}

func makeTheme(_ r: inout RNG, depth: Int) -> Theme {
    let places = ["Archive", "Hive", "Spire", "Cistern", "Foundry", "Reliquary", "Labyrinth", "Nest", "Observatory", "Catacomb"]
    let adj = ["Drowned", "Chitinous", "Psionic", "Ashen", "Weeping", "Shattered", "Hollow", "Burning", "Silent", "Dreaming"]
    let hue = CGFloat(r.unit())
    let sky = SKColor(hue: hue, saturation: 0.55, brightness: 0.10, alpha: 1)
    let rock = SKColor(hue: hue, saturation: 0.35, brightness: 0.24, alpha: 1)
    let edge = SKColor(hue: fmod(hue + 0.45, 1), saturation: 0.9, brightness: 1, alpha: 1)
    let mist = SKColor(hue: fmod(hue + 0.1, 1), saturation: 0.6, brightness: 0.35, alpha: 1)
    return Theme(name: "The \(r.pick(adj)) \(r.pick(places)) - Depth \(depth)", sky: sky, rock: rock, edge: edge, mist: mist)
}

func clamp<V: Comparable>(_ v: V, _ lo: V, _ hi: V) -> V { min(max(v, lo), hi) }

func label(_ text: String, size: CGFloat, color: SKColor = .white, bold: Bool = false) -> SKLabelNode {
    let l = SKLabelNode(fontNamed: bold ? "Menlo-Bold" : "Menlo")
    l.text = text; l.fontSize = size; l.fontColor = color
    l.horizontalAlignmentMode = .center; l.verticalAlignmentMode = .center
    return l
}
