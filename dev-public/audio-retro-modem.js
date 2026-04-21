// public/audio-retro-modem.js
(function () {
  'use strict';

  const { midiToFreq, mapRange } = MeshAudio.helpers;

  function clamp(x, lo, hi) {
    return Math.max(lo, Math.min(hi, x));
  }

  function byteAt(arr, i, fallback = 0) {
    return arr && arr.length ? arr[i % arr.length] : fallback;
  }

  function env(gainNode, t0, attack, peak, decay, sustain, release) {
    const g = gainNode.gain;
    g.cancelScheduledValues(t0);
    g.setValueAtTime(0.0001, t0);
    g.exponentialRampToValueAtTime(Math.max(0.0002, peak), t0 + attack);
    g.exponentialRampToValueAtTime(Math.max(0.0002, sustain), t0 + attack + decay);
    g.exponentialRampToValueAtTime(0.0001, t0 + attack + decay + release);
  }

  function chirp(audioCtx, masterGain, {
    t,
    f0,
    f1,
    dur,
    type = 'square',
    vol = 0.05,
    pan = 0,
    bandHz = 2200,
    q = 4
  }) {
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    const filter = audioCtx.createBiquadFilter();
    const panner = audioCtx.createStereoPanner();

    osc.type = type;
    osc.frequency.setValueAtTime(f0, t);
    osc.frequency.exponentialRampToValueAtTime(Math.max(40, f1), t + dur);

    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(bandHz, t);
    filter.Q.value = q;

    panner.pan.setValueAtTime(clamp(pan, -1, 1), t);

    osc.connect(filter);
    filter.connect(gain);
    gain.connect(panner);
    panner.connect(masterGain);

    env(gain, t, 0.004, vol, dur * 0.35, vol * 0.4, dur * 0.65);

    osc.start(t);
    osc.stop(t + dur + 0.02);

    osc.onended = () => {
      try { osc.disconnect(); filter.disconnect(); gain.disconnect(); panner.disconnect(); } catch (_) {}
    };
  }

  function clickBurst(audioCtx, masterGain, t, pan, vol) {
    const buffer = audioCtx.createBuffer(1, Math.floor(audioCtx.sampleRate * 0.018), audioCtx.sampleRate);
    const data = buffer.getChannelData(0);

    for (let i = 0; i < data.length; i++) {
      const decay = 1 - i / data.length;
      data[i] = (Math.random() * 2 - 1) * decay * decay;
    }

    const src = audioCtx.createBufferSource();
    const filter = audioCtx.createBiquadFilter();
    const gain = audioCtx.createGain();
    const panner = audioCtx.createStereoPanner();

    src.buffer = buffer;
    filter.type = 'highpass';
    filter.frequency.value = 1800;
    panner.pan.value = clamp(pan, -1, 1);

    gain.gain.setValueAtTime(vol, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.02);

    src.connect(filter);
    filter.connect(gain);
    gain.connect(panner);
    panner.connect(masterGain);

    src.start(t);
    src.stop(t + 0.025);

    src.onended = () => {
      try { src.disconnect(); filter.disconnect(); gain.disconnect(); panner.disconnect(); } catch (_) {}
    };
  }

  function typeProfile(typeName) {
    switch (typeName) {
      case 'TEXT_MESSAGE':
      case 'DIRECT_MESSAGE':
        return { base: 1200, sweep: 700, spacing: 0.055, osc: 'square' };
      case 'POSITION':
      case 'GPS':
        return { base: 1600, sweep: 500, spacing: 0.045, osc: 'triangle' };
      case 'NODEINFO':
      case 'TELEMETRY':
        return { base: 2100, sweep: 350, spacing: 0.035, osc: 'square' };
      default:
        return { base: 1450, sweep: 600, spacing: 0.05, osc: 'square' };
    }
  }

  function play(audioCtx, masterGain, parsed, opts) {
    const { payloadBytes, typeName, hopCount, obsCount, lon } = parsed;
    if (!payloadBytes || !payloadBytes.length) return 0.25;

    const now = audioCtx.currentTime;
    const tm = opts?.tempoMultiplier || 1;
    const profile = typeProfile(typeName);

    // Pan from longitude when available; otherwise derive lightly from bytes
    let pan = 0;
    if (typeof lon === 'number' && Number.isFinite(lon)) {
      pan = clamp(lon / 180, -0.9, 0.9);
    } else {
      pan = mapRange((byteAt(payloadBytes, 0) + byteAt(payloadBytes, 1)) / 2, 0, 255, -0.5, 0.5);
    }

    // More hops = duller/narrower "radio" tone
    const bandHz = mapRange(clamp(hopCount || 0, 0, 8), 0, 8, 2600, 1200);

    // More observations = slightly denser phrase
    const chirpCount = clamp(3 + Math.floor((obsCount || 0) / 2), 3, 8);

    for (let i = 0; i < chirpCount; i++) {
      const b0 = byteAt(payloadBytes, i * 2);
      const b1 = byteAt(payloadBytes, i * 2 + 1, 127);

      const t = now + i * profile.spacing * tm;

      // Old-modem-ish FSK sweep region
      const f0 = profile.base + mapRange(b0, 0, 255, -250, profile.sweep);
      const f1 = profile.base + mapRange(b1, 0, 255, 100, profile.sweep + 250);

      const dur = mapRange((b0 ^ b1) & 0xff, 0, 255, 0.025, 0.09) * tm;
      const vol = mapRange(b0, 0, 255, 0.018, 0.05);

      chirp(audioCtx, masterGain, {
        t,
        f0,
        f1,
        dur,
        type: profile.osc,
        vol,
        pan,
        bandHz,
        q: 5
      });

      // Add occasional little click/static accents
      if (((b0 + b1 + i) % 3) === 0) {
        clickBurst(audioCtx, masterGain, t + dur * 0.35, pan * 0.7, vol * 0.35);
      }
    }

    // Packet-end "ack" beep
    const tailT = now + chirpCount * profile.spacing * tm + 0.01;
    const tailMidi = 76 + ((byteAt(payloadBytes, 0) ^ byteAt(payloadBytes, payloadBytes.length - 1)) % 8);
    const tailFreq = midiToFreq(tailMidi);

    chirp(audioCtx, masterGain, {
      t: tailT,
      f0: tailFreq,
      f1: tailFreq * 0.98,
      dur: 0.04 * tm,
      type: 'triangle',
      vol: 0.03,
      pan: -pan * 0.4,
      bandHz: Math.max(1000, bandHz - 200),
      q: 6
    });

    return (chirpCount * profile.spacing + 0.09) * tm;
  }

  MeshAudio.registerVoice('retro-modem', {
    name: 'retro-modem',
    play
  });
})();
