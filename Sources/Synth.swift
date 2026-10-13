import AVFoundation
import os

/// Short procedural traversal/foley cues (v3 §7). All synthesized; no samples.
enum TraversalCue: UInt8, CaseIterable { case step, land, grab, climb, draw }

/// Fully procedural soundtrack. No samples: every kick, clap, hat, wobble and pad is synthesized live.
/// Two moods that crossfade: "explore" (128 BPM deep/tech-house) and "combat" (140 BPM half-time
/// dubstep with an LFO-wobbled, distorted bass and growl). Chord progression changes per rift seed.
///
/// Threading (v3 §7): the game thread only writes `pend` (controls, SFX triggers, a bounded cue mailbox)
/// under a short lock. The audio callback try-locks once per buffer, snapshots, and otherwise renders
/// with its previous controls; it never waits. Envelopes, phases, smoothing and buffers are audio-owned.
final class Synth {
    let engine = AVAudioEngine()
    private var node: AVAudioSourceNode!
    private let sr: Double = 44100

    // MARK: Game-thread control handoff
    private struct Controls {
        var target: Float = 0, master: Float = 0.55
        var root = 45, prog = (0, -4, 3, -2)
        var combat = false, lowHP = false
        // SFX triggers; < 0 means "no new trigger this buffer"
        var hit: Float = -1, zap: Float = -1, death: Float = -1, portal: Float = -1, whoosh: Float = -1, clang: Float = -1
        var cueCount = 0
    }
    static let cueCapacity = 16
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1); p.initialize(to: os_unfair_lock()); return p
    }()
    private var pend = Controls()                         // guarded by `lock`
    private let pendKind = UnsafeMutablePointer<UInt8>.allocate(capacity: Synth.cueCapacity)
    private let pendStr = UnsafeMutablePointer<Float>.allocate(capacity: Synth.cueCapacity)
    // Audio-side snapshot (only touched by the renderer)
    private var live = Controls()
    private let liveKind = UnsafeMutablePointer<UInt8>.allocate(capacity: Synth.cueCapacity)
    private let liveStr = UnsafeMutablePointer<Float>.allocate(capacity: Synth.cueCapacity)

    @inline(__always) private func withLock<R>(_ f: () -> R) -> R { os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }; return f() }

    var targetIntensity: Float { get { withLock { pend.target } } set { withLock { pend.target = newValue } } }
    var master: Float { get { withLock { pend.master } } set { withLock { pend.master = newValue } } }
    var root: Int = 45 { didSet { let r = root; withLock { pend.root = r } } }              // MIDI A2
    var progression: [Int] = [0, -4, 3, -2] {                                            // i - VI - III - VII
        didSet { let p = progression; guard p.count >= 4 else { return }; withLock { pend.prog = (p[0], p[1], p[2], p[3]) } }
    }

    // SFX triggers (same handoff; same-frame writes keep the strongest so impacts/clangs win)
    var sfxHit: Float { get { withLock { max(0, pend.hit) } } set { withLock { pend.hit = max(pend.hit, newValue) } } }
    var sfxZap: Float { get { withLock { max(0, pend.zap) } } set { withLock { pend.zap = max(pend.zap, newValue) } } }
    var sfxDeath: Float { get { withLock { max(0, pend.death) } } set { withLock { pend.death = max(pend.death, newValue) } } }
    var sfxPortal: Float { get { withLock { max(0, pend.portal) } } set { withLock { pend.portal = max(pend.portal, newValue) } } }
    var sfxWhoosh: Float { get { withLock { max(0, pend.whoosh) } } set { withLock { pend.whoosh = max(pend.whoosh, newValue) } } }
    var sfxClang: Float { get { withLock { max(0, pend.clang) } } set { withLock { pend.clang = max(pend.clang, newValue) } } }

    /// Queue a traversal cue. Bounded mailbox: duplicates coalesce (strongest wins); a full box drops the cue.
    func cue(_ cue: TraversalCue, strength: Float = 1) {
        let s = clamp(strength.isFinite ? strength : 0, 0, 1.5)
        withLock {
            for i in 0..<pend.cueCount where pendKind[i] == cue.rawValue { pendStr[i] = max(pendStr[i], s); return }
            guard pend.cueCount < Synth.cueCapacity else { return }
            pendKind[pend.cueCount] = cue.rawValue; pendStr[pend.cueCount] = s; pend.cueCount += 1
        }
    }
    /// Call on encounter / HP state changes only.
    func setSituation(combat: Bool, lowHP: Bool) { withLock { pend.combat = combat; pend.lowHP = lowHP } }
    /// Low-HP hysteresis: enter below 0.25, exit above 0.32.
    static func lowHPState(wasLow: Bool, fraction f: CGFloat) -> Bool { wasLow ? !(f > 0.32) : f < 0.25 }
    var pendingCueCount: Int { withLock { pend.cueCount } }

    // MARK: Audio-owned state
    private var intensity: Float = 0          // 0 explore -> 1 full drop
    private var eHit = 0.0, eZap = 0.0, eDeath = 0.0, ePortal = 0.0, eWhoosh = 0.0, eClang = 0.0
    private var whPh = 0.0, clPh = [0.0, 0.0, 0.0, 0.0], thPh = 0.0, wlp = 0.0, sidechain = 0.0
    private var t: Double = 0
    private var kPhase = 0.0, bPhase = 0.0, b2Phase = 0.0, subPhase = 0.0, arpPhase = 0.0
    private var padPh = [Double](repeating: 0, count: 6)
    private var lp = 0.0, bp = 0.0            // SVF for bass
    private var hpPrev = 0.0, hpOut = 0.0
    private var noise: UInt32 = 22222
    private var lastStep = -1
    private var kickEnv = 0.0, clapEnv = 0.0, hatEnv = 0.0, openHatEnv = 0.0, arpEnv = 0.0
    private var kickClick = 1e9, clapBody = 1e9, cbLP = 0.0, cbLP2 = 0.0   // ages in seconds
    private var arpNote = 0
    private var zPh = 0.0, pPh = 0.0
    private var reverbBuf = [Float](repeating: 0, count: 44100)
    private var rIdx = 0
    // Cue voices: ages (s), strengths, filter/phase state
    private var stepAge = 1e9, stepS = 0.0, lastStepCue = -1e9, stHP = 0.0, stPrev = 0.0
    private var landAge = 1e9, landS = 0.0, landPh = 0.0, landLP = 0.0
    private var grabAge = 1e9, grabS = 0.0, grLP1 = 0.0, grLP2 = 0.0, grPh = 0.0
    private var drawAge = 1e9, drawS = 0.0, drPh = (0.0, 0.0, 0.0)
    private var stingAge = 1e9, lastSting = -1e9, stPh = (0.0, 0.0), wasCombat = false
    private var lpMix = 0.0, mLP1L = 0.0, mLP2L = 0.0, mLP1R = 0.0, mLP2R = 0.0
    private var dcXL = 0.0, dcYL = 0.0, dcXR = 0.0, dcYR = 0.0
    // Offline-test observability (audio-owned counters)
    private(set) var stepsPlayed = 0, stingersPlayed = 0
    var lowPassMix: Double { lpMix }
    var testMusicOff = false                  // offline tests only: isolates SFX/cues

    // Hoisted per-sample constants
    private static let arpPattern = [0, 7, 12, 15, 12, 7, 3, 10]
    private let padRatio: [Double] = [0.0, 3, 7, 10, 12, 15].enumerated().map { k, iv in pow(2, (12 + iv) / 12) * (1 + Double(k) * 0.0013) }
    private let clangInc: [Double]
    private let duckRelease: Double, lpCoef: Double, lpSmooth: Double, dcR: Double

    init() {
        clangInc = [1.0, 2.76, 5.40, 8.93].map { 620 * $0 / 44100 }
        duckRelease = exp(-1 / (0.18 * 44100))
        lpCoef = 1 - exp(-2 * .pi * 1800 / 44100)
        lpSmooth = 1 - exp(-1 / (0.25 * 44100))
        dcR = 1 - 2 * .pi * 8 / 44100
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        node = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let L = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            let R = buffers[1].mData!.assumingMemoryBound(to: Float.self)
            self.beginBuffer()
            for i in 0..<Int(frames) {
                let (l, r) = self.render()
                L[i] = l; R[i] = r
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
    }

    func start() { try? engine.start() }

    func reseed(_ r: inout RNG) {
        let roots = [40, 41, 43, 45, 46, 38]
        root = r.pick(roots)
        let progs = [[0, -4, 3, -2], [0, 3, -2, -4], [0, -5, -4, -2], [0, 5, 3, -2], [0, -2, -4, -5]]
        progression = r.pick(progs)
    }

    /// Offline rendering for tests. Requires the engine stopped (never advances a live renderer twice).
    func renderTestFrames(_ count: Int) -> [(Float, Float)] {
        guard !engine.isRunning, count > 0 else { return [] }
        var out = [(Float, Float)](); out.reserveCapacity(count)
        for i in 0..<count {
            if i % 512 == 0 { beginBuffer() }
            out.append(render())
        }
        return out
    }

    /// Once per buffer: nonblocking snapshot of game-side controls. On contention keep previous controls.
    private func beginBuffer() {
        guard os_unfair_lock_trylock(lock) else { return }
        live = pend
        for i in 0..<pend.cueCount { liveKind[i] = pendKind[i]; liveStr[i] = pendStr[i] }
        pend.hit = -1; pend.zap = -1; pend.death = -1; pend.portal = -1; pend.whoosh = -1; pend.clang = -1; pend.cueCount = 0
        os_unfair_lock_unlock(lock)

        if live.hit >= 0 { eHit = Double(live.hit) }
        if live.zap >= 0 { eZap = Double(live.zap) }
        if live.death >= 0 { eDeath = Double(live.death) }
        if live.portal >= 0 { ePortal = Double(live.portal) }
        if live.whoosh >= 0 { eWhoosh = Double(live.whoosh) }
        if live.clang >= 0 { eClang = Double(live.clang) }
        for i in 0..<live.cueCount {
            let s = Double(liveStr[i])
            switch TraversalCue(rawValue: liveKind[i]) {
            case .step?: if t - lastStepCue >= 0.12 { stepAge = 0; stepS = s; lastStepCue = t; stepsPlayed += 1 }
            case .land?: landAge = 0; landS = s; landPh = 0
            case .grab?, .climb?: grabAge = 0; grabS = s
            case .draw?: drawAge = 0; drawS = s
            case nil: break
            }
        }
        live.cueCount = 0
        if live.combat && !wasCombat && t - lastSting >= 4 { stingAge = 0; lastSting = t; stingersPlayed += 1; stPh = (0, 0) }
        wasCombat = live.combat
    }

    @inline(__always) private func rnd() -> Double {
        noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5
        return Double(noise) / Double(UInt32.max) * 2 - 1
    }
    @inline(__always) private func mtof(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }
    @inline(__always) private func saw(_ p: Double) -> Double { 2 * (p - floor(p)) - 1 }
    /// Click-free one-shot envelope: 2 ms attack, quadratic decay to zero at `dur`.
    @inline(__always) private func oneShot(_ age: Double, _ dur: Double) -> Double {
        guard age < dur else { return 0 }
        let a = 1 - age / dur
        return min(1, age / 0.002) * a * a
    }

    private func render() -> (Float, Float) {
        intensity += (live.target - intensity) * 0.00003
        let I = Double(intensity)
        let bpm = 128 + 12 * I
        let spb = 60 / bpm                       // seconds per beat
        let stepLen = spb / 4                    // 16th note
        let stepF = t / stepLen
        let step = Int(stepF)
        let stepPos = stepF - Double(step)
        let bar = (step / 16) % 4
        let s16 = step % 16
        let halfTime = I > 0.55
        let dtS = 1 / sr

        if step != lastStep {
            lastStep = step
            // Kick: four-on-floor in house, beats 1 & (3 of half-time) in dubstep
            if (!halfTime && s16 % 4 == 0) || (halfTime && (s16 == 0 || s16 == 10)) { kickEnv = 1; kPhase = 0; kickClick = 0 }
            // Clap: 2 & 4 in house, beat 3 in half-time
            if (!halfTime && (s16 == 4 || s16 == 12)) || (halfTime && s16 == 8) { clapEnv = 1; clapBody = 0 }
            // Hats
            if s16 % 2 == 1 { openHatEnv = 0.8 } else if I > 0.3 { hatEnv = 0.5 }
            // Arp
            if s16 % 2 == 0 || I > 0.7 {
                arpNote = Synth.arpPattern[(step / 2) % Synth.arpPattern.count]
                arpEnv = 1
            }
        }

        let pr: Int
        switch bar { case 0: pr = live.prog.0; case 1: pr = live.prog.1; case 2: pr = live.prog.2; default: pr = live.prog.3 }
        let chord = Double(live.root + pr)

        // KICK: sine with fast downward pitch sweep + short 12 ms noise click
        kickEnv *= 0.99965
        let kf = 45 + 180 * kickEnv * kickEnv * kickEnv
        kPhase += kf / sr
        kickClick += dtS
        let kick = sin(2 * .pi * kPhase) * kickEnv * 1.1 + rnd() * oneShot(kickClick, 0.012) * 0.22

        // Sidechain pump from kick
        let duck = 1 - 0.75 * kickEnv

        // CLAP: filtered noise burst with a slight tone, plus a 90 ms band-passed noise body
        clapEnv *= 0.9993
        clapBody += dtS
        let cn = rnd()
        cbLP += 0.35 * (cn - cbLP); cbLP2 += 0.06 * (cbLP - cbLP2)
        let clap = (rnd() * 0.8 + sin(t * 2 * .pi * 190) * 0.2) * clapEnv * clapEnv * 0.55 + (cbLP - cbLP2) * oneShot(clapBody, 0.09) * 0.45

        // HATS: high-passed noise
        let n = rnd()
        hpOut = 0.92 * (hpOut + n - hpPrev); hpPrev = n
        hatEnv *= 0.997; openHatEnv *= 0.9992
        let hats = hpOut * (hatEnv * 0.18 + openHatEnv * 0.12)

        // SUB BASS (house): offbeat pluck on root (sustained bass at 0.85 of baseline)
        subPhase += mtof(chord - 12 + 12) / sr
        let houseEnv = halfTime ? 0 : max(0, 1 - abs(stepPos - 0.5) * 2) * (s16 % 4 == 2 ? 1 : 0.0)
        let sub = sin(2 * .pi * subPhase) * houseEnv * 0.5 * (1 - I) * 0.85

        // WOBBLE BASS (dubstep): two detuned saws -> resonant SVF lowpass, LFO-modulated cutoff
        let bf = mtof(chord - 12)
        bPhase += bf / sr; b2Phase += bf * 1.007 / sr
        let raw = saw(bPhase) + saw(b2Phase) * 0.8 + sin(2 * .pi * bPhase * 0.5) * 0.7
        let wobRate = (bar % 2 == 0) ? 2.0 : (s16 >= 8 ? 6.0 : 3.0)   // per beat
        let lfo = 0.5 + 0.5 * sin(2 * .pi * t / spb * wobRate)
        let cutoff = 90 + 2400 * lfo * lfo
        let f = 2 * sin(.pi * min(cutoff, 8000) / sr)
        let q = 0.25
        lp += f * bp
        let hp = raw - lp - q * bp
        bp += f * hp
        var wob = lp * 0.6 + bp * 0.25
        wob = tanh(wob * 2.8) * 0.55                  // growl / distortion
        wob *= I * (halfTime ? 1.0 : 0.4) * 0.85

        // PAD: supersaw-ish chord, minor triad + 7th (ratios precomputed)
        let padBase = mtof(chord) / sr
        var pad = 0.0
        for k in 0..<6 {
            padPh[k] += padBase * padRatio[k]
            pad += saw(padPh[k])
        }
        pad = pad / 6 * 0.11 * (1 - 0.5 * I)

        // ARP lead: square-ish pluck
        arpEnv *= 0.9996
        arpPhase += mtof(chord + 24 + Double(arpNote)) / sr
        let arp = (sin(2 * .pi * arpPhase) + 0.3 * saw(arpPhase * 2)) * arpEnv * arpEnv * 0.10

        // SFX (audio-owned envelopes retriggered from the per-buffer snapshot)
        eHit *= 0.9985; eZap *= 0.9993; eDeath *= 0.99985; ePortal *= 0.99993
        let fh = eHit, fz = eZap, fd = eDeath, fp = ePortal
        zPh += (300 + 1800 * fz) / sr
        pPh += (80 + 600 * (1 - fp)) / sr
        let s1: Double = rnd() * fh * 0.35
        let s2: Double = saw(zPh) * fz * 0.2
        let s3: Double = sin(2 * .pi * pPh) * fp * 0.3
        let s4: Double = rnd() * fd * fd * 0.25
        // Whoosh: band-passed noise with a falling sweep (sword cutting air); 0.75 of baseline level
        eWhoosh *= 0.99955
        let fw = eWhoosh
        let wn = rnd()
        let wc = 2 * sin(.pi * min(6000, 400 + 3200 * fw) / sr)
        wlp += wc * (wn - wlp)
        let s5: Double = wlp * fw * fw * 0.55 * 0.75
        // Clang: inharmonic metal partials (steel on steel) with fast decay
        eClang *= 0.99975
        let fc = eClang
        var clang = 0.0
        for k in 0..<4 { clPh[k] += clangInc[k]; clang += sin(2 * .pi * clPh[k]) / Double(k + 1) }
        let s6: Double = clang * fc * fc * 0.32 + rnd() * fc * fc * fc * 0.15
        // Impact thump: pitched-down body hit layered under the noise crack
        thPh += (55 + 140 * fh) / sr
        let s7: Double = sin(2 * .pi * thPh) * fh * fh * 0.6
        // Duck music under impacts (target 0.35, 0.18 s release) so they punch through the mix
        sidechain = max(sidechain * duckRelease, min(1, fh + fc))

        // Traversal cues
        stepAge += dtS; landAge += dtS; grabAge += dtS; drawAge += dtS; stingAge += dtS
        var cues = 0.0
        if stepAge < 0.045 {                       // tap: high-passed noise
            let x = rnd(); stHP = 0.7 * (stHP + x - stPrev); stPrev = x
            cues += stHP * oneShot(stepAge, 0.045) * 0.10 * stepS
        }
        if landAge < 0.10 {                        // low thump with a falling pitch
            landPh += (48 + 70 * (1 - landAge / 0.10)) / sr
            landLP += 0.08 * (rnd() - landLP)
            cues += (sin(2 * .pi * landPh) + landLP * 0.8) * oneShot(landAge, 0.10) * 0.22 * landS
        }
        if grabAge < 0.12 {                        // filtered breath/grunt
            let x = rnd(); grLP1 += 0.12 * (x - grLP1); grLP2 += 0.02 * (grLP1 - grLP2)
            grPh += (120 - 30 * grabAge / 0.12) / sr
            cues += ((grLP1 - grLP2) * 2.2 + sin(2 * .pi * grPh) * 0.25) * oneShot(grabAge, 0.12) * 0.16 * grabS
        }
        if drawAge < 0.13 {                        // high metallic scrape
            let sweep = 1 + 0.25 * drawAge / 0.13
            drPh.0 += 2400 * sweep / sr; drPh.1 += 3710 * sweep / sr; drPh.2 += 5130 * sweep / sr
            let metal = sin(2 * .pi * drPh.0) * 0.5 + sin(2 * .pi * drPh.1) * 0.3 + sin(2 * .pi * drPh.2) * 0.2
            cues += metal * (0.6 + 0.4 * rnd()) * oneShot(drawAge, 0.13) * 0.18 * drawS
        }
        if stingAge < 0.18 {                       // combat stinger: root+fifth stab with a noise hit
            let rootF = mtof(chord + 12)
            stPh.0 += rootF / sr; stPh.1 += rootF * 1.4983 / sr
            let e = oneShot(stingAge, 0.18)
            cues += (saw(stPh.0) * 0.5 + saw(stPh.1) * 0.35 + rnd() * e * 0.5) * e * 0.22
        }

        let sfx = s1 + s2 + s3 + s4 + s5 + s6 + s7 + cues

        let musicOn = testMusicOff ? 0.0 : 1.0
        let melodic: Double = (sub + wob + pad + arp) * duck * (1 - 0.65 * sidechain) * musicOn
        let drums: Double = (kick + clap + hats) * (1 - 0.5 * sidechain) * musicOn
        let music: Double = drums + melodic

        // Simple stereo echo (dotted 8th) on the existing buffer: wet 0.10, feedback 0.28
        let delay = Int(spb * 0.75 * sr) % reverbBuf.count
        let readIdx = (rIdx - delay + reverbBuf.count) % reverbBuf.count
        let echo = Double(reverbBuf[readIdx])
        reverbBuf[rIdx] = Float((pad + arp) * duck * musicOn + echo * 0.28)
        rIdx = (rIdx + 1) % reverbBuf.count
        var musL = music + echo * 0.10, musR = music + echo * 0.10 + arp * 0.1 * musicOn

        // Low-HP music low-pass (1800 Hz, 0.25 s smoothing); SFX bypass it and stay clear
        lpMix += ((live.lowHP ? 1 : 0) - lpMix) * lpSmooth
        mLP1L += lpCoef * (musL - mLP1L); mLP2L += lpCoef * (mLP1L - mLP2L)
        mLP1R += lpCoef * (musR - mLP1R); mLP2R += lpCoef * (mLP1R - mLP2R)
        musL += (mLP2L - musL) * lpMix; musR += (mLP2R - musR) * lpMix

        let m = Double(live.master)
        var l = tanh((musL + sfx) * 0.9) * m, r = tanh((musR + sfx) * 0.9) * m
        // DC blocker (~8 Hz) then hard bound
        let yl = l - dcXL + dcR * dcYL; dcXL = l; dcYL = yl
        let yr = r - dcXR + dcR * dcYR; dcXR = r; dcYR = yr
        l = clamp(yl, -1, 1); r = clamp(yr, -1, 1)
        t += dtS
        return (Float(l), Float(r))
    }
}
