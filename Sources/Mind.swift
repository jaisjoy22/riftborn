import Foundation

// MARK: - Persistent consequences

enum Faction: String, Codable, CaseIterable {
    case hive = "The Hive", wardens = "Iron Wardens", echoes = "The Echoes"
}

enum Motive: String, Codable, CaseIterable {
    case vengeance, duty, hunger, faith, fear, redemption, curiosity
}

/// A named being. Enemies and wanderers alike are Souls; they persist across rifts.
struct Soul: Codable {
    var id: Int
    var name: String
    var faction: Faction
    var motive: Motive
    var backstory: String
    var kinOf: Int? = nil          // the soul whose fate created this one
    var grudge: Int = 0            // 0 neutral, >0 hostile memory of the player
    var debt: Int = 0              // >0 owes the player (spared / helped)
    var alive = true
    var metCount = 0
    var level = 1
}

struct Chronicle: Codable {
    var seed: UInt64 = UInt64(Date().timeIntervalSince1970)
    var depth = 1
    var souls: [Soul] = []
    var nextId = 1
    var rep: [String: Int] = [:]     // faction rawValue -> reputation
    var log: [String] = []
    var mercy = 0, cruelty = 0
    var xp = 0, level = 1, shards = 0
    var maxHP = 100, power = 10
    var powers: [String] = []        // learned powers
    var choicesAtPortal: [String] = []
    var mutator = "None"
    var deaths = 0

    func repOf(_ f: Faction) -> Int { rep[f.rawValue] ?? 0 }
    mutating func shift(_ f: Faction, _ d: Int) { rep[f.rawValue] = repOf(f) + d }
    mutating func note(_ s: String) { log.append("[D\(depth)] " + s); if log.count > 200 { log.removeFirst() } }

    var alignment: String {
        if mercy > cruelty + 3 { return "the Merciful" }
        if cruelty > mercy + 3 { return "the Dread" }
        return "the Undecided"
    }

    static var url: URL {
        if let p = ProcessInfo.processInfo.environment["RIFTBORN_SAVE"] { return URL(fileURLWithPath: p) }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Riftborn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chronicle.json")
    }
    static func load() -> Chronicle {
        if let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Chronicle.self, from: d) { return c }
        return Chronicle()
    }
    func save() { if let d = try? JSONEncoder().encode(self) { try? d.write(to: Chronicle.url) } }
}

// MARK: - Mind: the generator of beings, stories and speech

enum Mind {
    static let first = ["Vashti", "Kerran", "Oru", "Selket", "Dagan", "Ithra", "Mozz", "Talvane", "Rhea", "Zeru", "Kasimir", "Nyx", "Barek", "Ilun", "Saffa", "Tor", "Quell", "Amaru"]
    static let epithet = ["the Hollow", "Who Counts", "of the Ninth Brood", "the Last Warden", "Ashtongue", "the Patient", "Blind-Eye", "the Unforgiven", "Glasshand", "the Hungering", "Twice-Born", "the Quiet"]

    static func newSoul(_ c: inout Chronicle, _ r: inout RNG, faction: Faction? = nil, motive: Motive? = nil, kinOf: Int? = nil) -> Soul {
        let f = faction ?? r.pick(Faction.allCases)
        let m = motive ?? r.pick(Motive.allCases)
        let name = "\(r.pick(first)) \(r.pick(epithet))"
        var s = Soul(id: c.nextId, name: name, faction: f, motive: m, backstory: "", kinOf: kinOf)
        s.backstory = story(s, c, &r)
        s.level = max(1, c.depth / 2 + r.range(0, 2))
        c.nextId += 1
        c.souls.append(s)
        return s
    }

    static func story(_ s: Soul, _ c: Chronicle, _ r: inout RNG) -> String {
        if let k = s.kinOf, let dead = c.souls.first(where: { $0.id == k }) {
            return r.pick([
                "\(dead.name) raised me. You left them cold on the stone.",
                "I carry \(dead.name)'s blade. It remembers your face.",
                "They told me \(dead.name) died begging. I came to hear you say it."
            ])
        }
        switch s.motive {
        case .vengeance: return r.pick(["The last rift-walker burned my brood. You wear the same light.", "I have sharpened one claw for thirty cycles. It has your name."])
        case .duty: return r.pick(["I guard this threshold because no one relieved me. No one ever will.", "The Wardens swore an oath to a king long dead. I still keep it."])
        case .hunger: return r.pick(["The Hive starves. Your shards could feed a thousand larvae.", "I am not cruel. I am hungry. There is a difference, rift-walker."])
        case .faith: return r.pick(["The Echo-Mother dreams this place. You are a nightmare she wants ended.", "Every rift is a prayer. You are interrupting mine."])
        case .fear: return r.pick(["Please. They make us fight. If I don't, the Overmind unmakes me.", "I've seen what's at the bottom. I won't let you open it."])
        case .redemption: return r.pick(["I opened the first rift. Every monster here is my fault.", "I betrayed my sworn-kin once. I will not do it again."])
        case .curiosity: return r.pick(["You are the first thing in a hundred cycles I didn't understand.", "I want to see where your path ends. Even if it ends me."])
        }
    }

    /// Opening line when the player approaches a being.
    static func greet(_ s: Soul, _ c: Chronicle, _ r: inout RNG) -> String {
        if s.debt > 0 { return r.pick(["You spared me. I haven't decided what that means.", "I owe you breath. I pay my debts."]) }
        if s.grudge > 1 { return r.pick(["You again. This time I came prepared.", "I counted every step you took since we last met."]) }
        let tone = c.repOf(s.faction)
        if tone < -4 { return "Your name is a curse among \(s.faction.rawValue). " + s.backstory }
        if tone > 4 { return "\(s.faction.rawValue) speak well of you. Strange. " + s.backstory }
        return s.backstory
    }

    /// Two options the player can choose: mercy-ish and dominance-ish, shaped by motive.
    static func choices(_ s: Soul) -> (String, String) {
        switch s.motive {
        case .vengeance: return ("Apologize for what was done", "Tell them grief makes them weak")
        case .duty:      return ("Release them from their oath", "Order them to kneel")
        case .hunger:    return ("Give 5 shards to feed the Hive", "Take what little they have")
        case .faith:     return ("Ask about the Echo-Mother", "Mock their dreaming god")
        case .fear:      return ("Promise to protect them", "Use their fear against them")
        case .redemption:return ("Offer them a second chance", "Say some sins stay")
        case .curiosity: return ("Invite them to walk with you", "Warn them away")
        }
    }

    /// Resolve a choice. Returns (reply, becomesAlly, becomesHostile).
    static func resolve(_ s: inout Soul, choice: Int, _ c: inout Chronicle, _ r: inout RNG) -> (String, Bool, Bool) {
        if choice == 0 {
            if s.motive == .hunger {
                guard c.shards >= 5 else { return ("You have nothing. Then you are food.", false, true) }
                c.shards -= 5
            }
            let trust = s.debt * 2 + c.repOf(s.faction) + c.mercy - s.grudge * 2 + r.range(-2, 4)
            c.mercy += 1; c.shift(s.faction, 2)
            if trust >= 1 || s.motive == .fear || s.motive == .redemption {
                s.debt += 1; s.grudge = 0
                c.note("\(s.name) stood down. \(s.faction.rawValue) will hear of it.")
                return (r.pick(["...Go. Before I remember why I came.", "Then I'll fight beside you. For now.", "Nobody has said that to me before."]), true, false)
            }
            c.note("\(s.name) refused mercy.")
            return (r.pick(["Words. I came for blood.", "Mercy is a luxury of the living."]), false, true)
        } else {
            c.cruelty += 1; c.shift(s.faction, -2)
            if s.motive == .fear || (s.level < c.level - 1 && r.chance(0.6)) {
                s.grudge += 2
                c.shards += 3
                c.note("\(s.name) fled in terror. They will not forget.")
                return ("I- I'll go. I'll go.", false, false)
            }
            s.grudge += 1
            c.note("\(s.name) answered cruelty with steel.")
            return (r.pick(["Then we finish this.", "So be it, rift-walker."]), false, true)
        }
    }

    static func deathLine(_ s: Soul, _ r: inout RNG) -> String {
        switch s.motive {
        case .vengeance: return "Someone... will finish... this."
        case .duty: return "Relieved... at last."
        case .hunger: return "Feed... them..."
        case .faith: return "The Mother... wakes..."
        case .fear: return "I told them... I told them..."
        case .redemption: return "Not... enough..."
        case .curiosity: return r.pick(["So that's... the end.", "Show me... what's next."])
        }
    }

    static let allPowers = ["Psi Storm", "Blink", "Chrono Slow", "Swarm Spawn", "Overcharge"]

    static func portalProphecy(_ c: Chronicle) -> String {
        let lines = [
            "The rift reshapes itself around what you've become: \(c.alignment).",
            "Mercies: \(c.mercy). Cruelties: \(c.cruelty). The deeper places are listening.",
            c.repOf(.hive) < -4 ? "The Hive has marked you. Its broods gather below." : "The Hive watches, undecided.",
            c.repOf(.wardens) > 4 ? "The Wardens open hidden doors for you." : "The Wardens' gates stay sealed."
        ]
        return lines.joined(separator: "\n")
    }
}
