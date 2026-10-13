import AVFoundation

/// Fully procedural soundtrack. No samples: every kick, clap, hat, wobble and pad is synthesized live.
/// Two moods that crossfade: "explore" (128 BPM deep/tech-house) and "combat" (140 BPM half-time
/// dubstep with an LFO-wobbled, distorted bass and growl). Chord progression changes per rift seed.
final class Synth {
    let engine = AVAudioEngine()
    private var node: AVAudioSourceNode!
    private let sr: Double = 44100

    // Shared with the game thread (word-sized writes; benign races only affect the next sample).
    var intensity: Float = 0          // 0 explore -> 1 full drop
    var targetIntensity: Float = 0
    var master: Float = 0.55
    var root: Int = 45                // MIDI A2
    var progression: [Int] = [0, -4, 3, -2]   // i - VI - III - VII (relative semitones)

    // SFX triggers
    var sfxHit: Float = 0, sfxZap: Float = 0, sfxDeath: Float = 0, sfxPortal: Float = 0
    var sfxWhoosh: Float = 0, sfxClang: Float = 0
    private var whPh = 0.0, clPh = [0.0, 0.0, 0.0, 0.0], thPh = 0.0, wlp = 0.0, sidechain = 0.0

    // DSP state
    private var t: Double = 0
    private var kPhase = 0.0, bPhase = 0.0, b2Phase = 0.0, subPhase = 0.0, arpPhase = 0.0
    private var padPh = [Double](repeating: 0, count: 6)
    private var lp = 0.0, bp = 0.0            // SVF for bass
    private var hpPrev = 0.0, hpOut = 0.0
    private var noise: UInt32 = 22222
    private var lastStep = -1
    private var kickEnv = 0.0, clapEnv = 0.0, hatEnv = 0.0, openHatEnv = 0.0, arpEnv = 0.0
    private var arpNote = 0
    private var zPh = 0.0, pPh = 0.0
    private var reverbBuf = [Float](repeating: 0, count: 44100)
    private var rIdx = 0

    init() {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        node = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let L = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            let R = buffers[1].mData!.assumingMemoryBound(to: Float.self)
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

    @inline(__always) private func rnd() -> Double {
        noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5
        return Double(noise) / Double(UInt32.max) * 2 - 1
    }
    @inline(__always) private func mtof(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }
    @inline(__always) private func saw(_ p: Double) -> Double { 2 * (p - floor(p)) - 1 }

    private func render() -> (Float, Float) {
        intensity += (targetIntensity - intensity) * 0.00003
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

        if step != lastStep {
            lastStep = step
            // Kick: four-on-floor in house, beats 1 & (3 of half-time) in dubstep
            if (!halfTime && s16 % 4 == 0) || (halfTime && (s16 == 0 || s16 == 10)) { kickEnv = 1; kPhase = 0 }
            // Clap: 2 & 4 in house, beat 3 in half-time
            if (!halfTime && (s16 == 4 || s16 == 12)) || (halfTime && s16 == 8) { clapEnv = 1 }
            // Hats
            if s16 % 2 == 1 { openHatEnv = 0.8 } else if I > 0.3 { hatEnv = 0.5 }
            // Arp
            if s16 % 2 == 0 || I > 0.7 {
                let pattern = [0, 7, 12, 15, 12, 7, 3, 10]
                arpNote = pattern[(step / 2) % pattern.count]
                arpEnv = 1
            }
        }

        let chord = Double(root + progression[bar])

        // KICK: sine with fast downward pitch sweep
        kickEnv *= 0.99965
        let kf = 45 + 180 * kickEnv * kickEnv * kickEnv
        kPhase += kf / sr
        let kick = sin(2 * .pi * kPhase) * kickEnv * 1.1

        // Sidechain pump from kick
        let duck = 1 - 0.75 * kickEnv

        // CLAP: filtered noise burst with a slight tone
        clapEnv *= 0.9993
        let clap = (rnd() * 0.8 + sin(t * 2 * .pi * 190) * 0.2) * clapEnv * clapEnv * 0.55

        // HATS: high-passed noise
        let n = rnd()
        hpOut = 0.92 * (hpOut + n - hpPrev); hpPrev = n
        hatEnv *= 0.997; openHatEnv *= 0.9992
        let hats = hpOut * (hatEnv * 0.18 + openHatEnv * 0.12)

        // SUB BASS (house): offbeat pluck on root
        subPhase += mtof(chord - 12 + 12) / sr
        let houseEnv = halfTime ? 0 : max(0, 1 - abs(stepPos - 0.5) * 2) * (s16 % 4 == 2 ? 1 : 0.0)
        let sub = sin(2 * .pi * subPhase) * houseEnv * 0.5 * (1 - I)

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
        wob *= I * (halfTime ? 1.0 : 0.4)

        // PAD: supersaw-ish chord, minor triad + 7th
        let intervals: [Double] = [0, 3, 7, 10, 12, 15]
        var pad = 0.0
        for k in 0..<6 {
            padPh[k] += mtof(chord + 12 + intervals[k]) * (1 + Double(k) * 0.0013) / sr
            pad += saw(padPh[k])
        }
        pad = pad / 6 * 0.11 * (1 - 0.5 * I)

        // ARP lead: square-ish pluck
        arpEnv *= 0.9996
        arpPhase += mtof(chord + 24 + Double(arpNote)) / sr
        let arp = (sin(2 * .pi * arpPhase) + 0.3 * saw(arpPhase * 2)) * arpEnv * arpEnv * 0.10

        // SFX (Float triggers set by game thread; convert to Double locally)
        sfxHit *= 0.9985; sfxZap *= 0.9993; sfxDeath *= 0.99985; sfxPortal *= 0.99993
        let fh = Double(sfxHit), fz = Double(sfxZap), fd = Double(sfxDeath), fp = Double(sfxPortal)
        zPh += (300 + 1800 * fz) / sr
        pPh += (80 + 600 * (1 - fp)) / sr
        let s1: Double = rnd() * fh * 0.35
        let s2: Double = saw(zPh) * fz * 0.2
        let s3: Double = sin(2 * .pi * pPh) * fp * 0.3
        let s4: Double = rnd() * fd * fd * 0.25
        // Whoosh: band-passed noise with a falling sweep (sword cutting air)
        sfxWhoosh *= 0.99955
        let fw = Double(sfxWhoosh)
        let wn = rnd()
        let wc = 2 * sin(.pi * min(6000, 400 + 3200 * fw) / sr)
        wlp += wc * (wn - wlp)
        let s5: Double = (wn - wlp) * 0 + wlp * fw * fw * 0.55
        // Clang: inharmonic metal partials (steel on steel) with fast decay
        sfxClang *= 0.99975
        let fc = Double(sfxClang)
        let ratios = [1.0, 2.76, 5.40, 8.93]
        var clang = 0.0
        for k in 0..<4 { clPh[k] += 620 * ratios[k] / sr; clang += sin(2 * .pi * clPh[k]) / Double(k + 1) }
        let s6: Double = clang * fc * fc * 0.32 + rnd() * fc * fc * fc * 0.15
        // Impact thump: pitched-down body hit layered under the noise crack
        thPh += (55 + 140 * fh) / sr
        let s7: Double = sin(2 * .pi * thPh) * fh * fh * 0.6
        // Duck music under heavy impacts so they punch through the mix
        sidechain = max(sidechain * 0.9997, min(1, fh + fc))
        let sfx = s1 + s2 + s3 + s4 + s5 + s6 + s7

        let melodic: Double = (sub + wob + pad + arp) * duck * (1 - 0.45 * sidechain)
        let drums: Double = (kick + clap + hats) * (1 - 0.3 * sidechain)
        var mono: Double = drums + melodic + sfx

        // Simple stereo echo (dotted 8th) for space
        let delay = Int(spb * 0.75 * sr) % reverbBuf.count
        let readIdx = (rIdx - delay + reverbBuf.count) % reverbBuf.count
        let echo = Double(reverbBuf[readIdx])
        reverbBuf[rIdx] = Float((pad + arp) * duck + echo * 0.45)
        rIdx = (rIdx + 1) % reverbBuf.count

        mono = tanh(mono * 0.9)
        let m = Double(master)
        t += 1 / sr
        return (Float((mono + echo * 0.35) * m), Float((mono + echo * 0.25 + arp * 0.1) * m))
    }
}
