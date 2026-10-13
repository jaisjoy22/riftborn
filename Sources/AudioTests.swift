import SpriteKit

// MARK: - v3 phase 7 selftest: audio refinement (named failures; offline synth renders; isolated scenes)

private func stats(_ f: [(Float, Float)]) -> (finite: Bool, peak: Float, meanL: Double, meanR: Double) {
    var finite = true, peak: Float = 0, sl = 0.0, sr = 0.0
    for (l, r) in f {
        if !l.isFinite || !r.isFinite { finite = false; continue }
        peak = max(peak, abs(l), abs(r)); sl += Double(l); sr += Double(r)
    }
    let n = Double(max(1, f.count))
    return (finite, peak, sl / n, sr / n)
}

private func rms(_ f: ArraySlice<(Float, Float)>) -> Double {
    var s = 0.0
    for (l, r) in f { s += Double(l * l + r * r) / 2 }
    return (s / Double(max(1, f.count))).squareRoot()
}

/// Returns failures; also used by `--audiotest`.
func runV3AudioTests(_ failures: inout [String]) {
    let sr = 44100
    // 1. Each cue (plus legacy SFX) renders nonzero, finite, bounded output with a decaying tail.
    typealias Trigger = (String, (Synth) -> Void, Double)     // name, trigger, nominal duration (s)
    var triggers: [Trigger] = TraversalCue.allCases.map { c in
        let d: Double = [.step: 0.045, .land: 0.10, .grab: 0.12, .climb: 0.12, .draw: 0.13][c] ?? 0.1
        return ("\(c)", { $0.cue(c, strength: 1) }, d)
    }
    triggers += [("hit", { $0.sfxHit = 1.6 }, 0.25), ("clang", { $0.sfxClang = 1.5 }, 0.3), ("whoosh", { $0.sfxWhoosh = 1.5 }, 0.25),
                 ("stinger", { $0.setSituation(combat: true, lowHP: false) }, 0.18)]
    for (name, fire, dur) in triggers {
        let s = Synth(); s.testMusicOff = true
        _ = s.renderTestFrames(1024)                          // settle; previous controls
        fire(s)
        let f = s.renderTestFrames(Int((dur + 0.1) * Double(sr)))
        let st = stats(f)
        let tag = "v3 audio \(name)"
        if f.isEmpty { failures.append("\(tag): offline render refused"); continue }
        if !st.finite { failures.append("\(tag): non-finite sample") }
        if st.peak <= 1e-4 { failures.append("\(tag): cue produced no output") }
        if st.peak > 1 { failures.append("\(tag): sample outside [-1, 1] (\(st.peak))") }
        // Tail: after a short attack, RMS of successive windows falls and the cue ends near-silent.
        let a = Int(0.01 * Double(sr)), mid = a + Int(dur * Double(sr) * 0.4), end = Int(dur * Double(sr))
        let early = rms(f[a..<mid]), late = rms(f[mid..<end]), after = rms(f[(end + Int(0.05 * Double(sr)))..<f.count])
        if !(late < early) { failures.append("\(tag): tail RMS did not decay (\(early) -> \(late))") }
        if name != "hit" && name != "clang" && name != "whoosh" && !(after < early * 0.2) {
            failures.append("\(tag): cue tail did not die out (\(after) vs \(early))")
        }
    }

    // 2. Fixed 2-second mixed-cue render with music on: finite, bounded, no DC drift, no runaway feedback.
    do {
        let s = Synth(); s.targetIntensity = 1
        var f: [(Float, Float)] = []; f.reserveCapacity(2 * sr)
        for b in 0..<(2 * sr / 512) {
            switch b % 24 {
            case 0: s.cue(.step); s.sfxHit = 1.6; s.sfxClang = 1.3      // stacked impacts in one frame
            case 4: s.cue(.land, strength: 1); s.sfxWhoosh = 1.5
            case 8: s.cue(.grab); s.cue(.draw); s.sfxHit = 1; s.sfxHit = 1.6; s.sfxClang = 1.5
            case 12: s.setSituation(combat: b % 48 == 12, lowHP: b > 80)
            case 16: s.cue(.climb); s.sfxZap = 1; s.sfxDeath = 1
            default: break
            }
            f += s.renderTestFrames(512)
        }
        let st = stats(f)
        if !st.finite { failures.append("v3 audio mix: non-finite sample") }
        if st.peak > 1 { failures.append("v3 audio mix: output unbounded (\(st.peak))") }
        if st.peak < 0.01 { failures.append("v3 audio mix: silent") }
        if abs(st.meanL) >= 0.02 || abs(st.meanR) >= 0.02 { failures.append("v3 audio mix: DC drift (L \(st.meanL), R \(st.meanR))") }
        // Runaway feedback check: with everything stopped, 3 s later the SFX/echo energy has decayed.
        let s2 = Synth(); s2.testMusicOff = true
        for _ in 0..<40 { s2.sfxHit = 1.6; s2.sfxClang = 1.5; s2.cue(.land); _ = s2.renderTestFrames(512) }
        let hot = rms(s2.renderTestFrames(sr / 4)[...])
        _ = s2.renderTestFrames(3 * sr)
        let cold = rms(s2.renderTestFrames(sr / 4)[...])
        if !(cold < hot * 0.05) { failures.append("v3 audio: runaway feedback (\(hot) -> \(cold))") }
    }

    // 3. Control handoff: bounded, coalescing cue mailbox; step minimum interval; stinger cooldown.
    do {
        let s = Synth()
        for _ in 0..<10 { s.cue(.step) }
        if s.pendingCueCount != 1 { failures.append("v3 audio mailbox: duplicate footsteps not coalesced (\(s.pendingCueCount))") }
        for i in 0..<64 { s.cue(TraversalCue.allCases[i % TraversalCue.allCases.count], strength: Float(i % 3)) }
        if s.pendingCueCount > Synth.cueCapacity { failures.append("v3 audio mailbox: grew past capacity (\(s.pendingCueCount))") }
        _ = s.renderTestFrames(512)
        if s.pendingCueCount != 0 { failures.append("v3 audio mailbox: not drained by the renderer") }
        s.cue(.step, strength: .nan); _ = s.renderTestFrames(512)
        if !stats(s.renderTestFrames(4096)).finite { failures.append("v3 audio: NaN cue strength leaked into output") }

        let st = Synth(); st.testMusicOff = true
        for _ in 0..<(sr / 512) { st.cue(.step); _ = st.renderTestFrames(512) }       // a step every 11.6 ms for 1 s
        if st.stepsPlayed > 9 || st.stepsPlayed < 7 { failures.append("v3 audio: step minimum interval 0.12 s violated (\(st.stepsPlayed)/s)") }

        let sg = Synth(); sg.testMusicOff = true
        for (i, c) in [true, false, true, false, true].enumerated() { sg.setSituation(combat: c, lowHP: false); _ = sg.renderTestFrames(sr / 2 + i) }
        if sg.stingersPlayed != 1 { failures.append("v3 audio: stinger cooldown not honored (\(sg.stingersPlayed) in 2.5 s)") }
        _ = sg.renderTestFrames(2 * sr)
        sg.setSituation(combat: false, lowHP: false); _ = sg.renderTestFrames(512)
        sg.setSituation(combat: true, lowHP: false); _ = sg.renderTestFrames(512)
        if sg.stingersPlayed != 2 { failures.append("v3 audio: stinger did not re-arm after 4 s (\(sg.stingersPlayed))") }
    }

    // 4. Low-HP: hysteresis (enter < 0.25, exit > 0.32) and a smoothed music low-pass.
    do {
        var low = false, flips = 0
        for f: CGFloat in [0.5, 0.3, 0.26, 0.249, 0.27, 0.31, 0.32, 0.30, 0.321, 0.31, 0.26, 0.24] {
            let n = Synth.lowHPState(wasLow: low, fraction: f); if n != low { flips += 1 }; low = n
        }
        if flips != 3 || !low { failures.append("v3 audio: low-HP hysteresis wrong (flips \(flips), low \(low))") }
        let s = Synth()
        s.setSituation(combat: false, lowHP: true)
        _ = s.renderTestFrames(512); let first = s.lowPassMix
        _ = s.renderTestFrames(sr)
        let entered = s.lowPassMix
        s.setSituation(combat: false, lowHP: false); _ = s.renderTestFrames(sr)
        if !(first < 0.2 && entered > 0.95 && s.lowPassMix < 0.05) {
            failures.append("v3 audio: low-HP low-pass smoothing wrong (\(first), \(entered), \(s.lowPassMix))")
        }
        // Low-pass must not bury SFX: a clang under low-HP stays as loud as without it.
        func clangPeak(_ lowHP: Bool) -> Float {
            let c = Synth(); c.testMusicOff = true; c.setSituation(combat: false, lowHP: lowHP); _ = c.renderTestFrames(sr / 2)
            c.sfxClang = 1.5; return stats(c.renderTestFrames(sr / 5)).peak
        }
        let a = clangPeak(false), b = clangPeak(true)
        if abs(a - b) > 0.02 * max(a, 1e-3) { failures.append("v3 audio: low-HP filter affected SFX (\(a) vs \(b))") }
    }

    // 5. Scene wiring: footsteps from grounded displacement only; none when idle, blocked or hanging.
    do {
        let inp = Input.shared
        let wasSuppressed = inp.suppressHardware
        inp.suppressHardware = true
        defer { inp.suppressHardware = wasSuppressed; resetTestInput(inp) }
        let s = GameScene(size: CGSize(width: 1440, height: 900))
        prepareV3Fixture(s, .overview); resetTestInput(inp)
        advanceTest(s, frames: 60, acts: [])
        var log: [TraversalCue] = []
        s.player.onTraversal = { c, _ in log.append(c) }
        advanceTest(s, frames: 60, acts: [])
        if !log.isEmpty { failures.append("v3 audio scene: idle player emitted \(log)") }
        advanceTest(s, frames: 40, acts: [.left])                // walk into the arena's left wall
        let walked = log.filter { $0 == .step }.count
        if walked == 0 { failures.append("v3 audio scene: walking produced no footsteps") }
        log.removeAll(); advanceTest(s, frames: 40, acts: [.left])
        if log.contains(.step) { failures.append("v3 audio scene: footsteps while blocked against a wall") }
        log.removeAll()
        s.player.moveMode = .hang
        advanceTest(s, frames: 30, acts: [.right])
        if log.first != .grab || log.contains(.step) { failures.append("v3 audio scene: hang cues wrong \(log)") }
        s.player.moveMode = .free
        advanceTest(s, frames: 30, acts: [])
        log.removeAll()
        advanceTest(s, frames: 1, acts: [.jump]); advanceTest(s, frames: 14, acts: [.jump])
        let airborneSteps = log.filter { $0 == .step }.count
        advanceTest(s, frames: 60, acts: [])
        if airborneSteps != 0 { failures.append("v3 audio scene: footsteps while airborne") }
        if !log.contains(.land) && !log.contains(.step) { failures.append("v3 audio scene: landing produced no contact cue \(log)") }
        log.removeAll()
        s.mode = .paused; advanceTest(s, frames: 30, acts: [.right]); s.mode = .play
        if !log.isEmpty { failures.append("v3 audio scene: cues while paused \(log)") }
        // Draw scrape: first strike after >= 1.5 s idle only.
        log.removeAll()
        advanceTest(s, frames: 100, acts: [])
        advanceTest(s, frames: 1, acts: [.attack]); advanceTest(s, frames: 40, acts: [])
        advanceTest(s, frames: 1, acts: [.attack]); advanceTest(s, frames: 40, acts: [])
        if log.filter({ $0 == .draw }).count != 1 { failures.append("v3 audio scene: draw cue count wrong \(log)") }
        // Situation calls happen on change only.
        let before = s.situationChanges
        advanceTest(s, frames: 120, acts: [])
        if s.situationChanges != before { failures.append("v3 audio scene: setSituation called without a state change") }
        s.player.hp = s.player.maxHP * 0.2; advanceTest(s, frames: 2, acts: [])
        if !s.audioLowHP { failures.append("v3 audio scene: low HP not entered") }
        s.player.hp = s.player.maxHP * 0.3; advanceTest(s, frames: 2, acts: [])
        if !s.audioLowHP { failures.append("v3 audio scene: low HP chattered at 0.30") }
        s.player.hp = s.player.maxHP; advanceTest(s, frames: 2, acts: [])
        if s.audioLowHP { failures.append("v3 audio scene: low HP not exited") }
    }
    print("  v3 audio         : \(TraversalCue.allCases.count) cues + 4 sfx offline, mixed 2 s render, mailbox cap \(Synth.cueCapacity), low-HP hysteresis")
}
