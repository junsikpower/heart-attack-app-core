# Heart Attack

A game that quantifies your heartbeat: through conversation, the player who raises the opponent's heart rate first wins. The opponent is either an AI character or another user.

This development cycle focused on the **camera-based heart rate (PPG) measurement engine**.
The game features (single- and multiplayer) are at working-MVP level, and this repository documents how the PPG measurement was stabilized.

**Stack**

- Platform: Flutter 3.11.4 (Android / iOS)
- State management: Riverpod (StateNotifier)
- Heart rate: `camera` + `flutter_ppg` + custom correction layer
- Single player: Gemini 2.5 Flash + `flutter_tts` + `speech_to_text`
- Multiplayer: Firebase Realtime Database + Agora RTC
- Data collection: Cloud Firestore

---

## Table of Contents

1. [Background](#1-background)
2. [Architecture](#2-architecture)
3. [Completion Status](#3-completion-status)
4. [PPG Implementation Process](#4-ppg-implementation-process)
   - [Stage 1 — Custom algorithm](#stage-1--custom-algorithm)
   - [Stage 2 — Field log collection and root cause analysis](#stage-2--field-log-collection-and-root-cause-analysis)
   - [Stage 3 — Adopting flutter_ppg and the two-track correction logic](#stage-3--adopting-flutter_ppg-and-the-two-track-correction-logic)
   - [Stage 4 — Limits of the rear camera approach](#stage-4--limits-of-the-rear-camera-approach)
   - [Stage 5 — Switching to front camera + display illumination](#stage-5--switching-to-front-camera--display-illumination)
5. [Next Steps](#5-next-steps)
6. [Getting Started](#6-getting-started)

---

## 1. Background

People are becoming more individualized and increasingly find real-world interaction burdensome. Yet the loneliness caused by a lack of interaction remains, and people try to substitute it with services such as social media. The problem is that those substitutes sit at two extremes.

- Services built on anonymity (random chat and similar) are easily contaminated by illicit use.
- Services built on transparency expose personal information to an unspecified audience, so they fail to remove the burden of interaction, and they are less entertaining than anonymous ones.

Heart Attack is built on four core values.

1. Use a game to remove the burden of real-world interaction.
2. Relieve loneliness and create engagement through interaction.
3. Make the interaction itself the objective to be conquered, driving the will to play.
4. Include heart rate as a game element, letting players observe emotional changes that are invisible in real life.

The fourth value is the identity of this project and also its largest technical risk. If the heart rate cannot be trusted, the game does not work at all. Accordingly, the top priority of this cycle was **establishing reliable heart rate measurement**.

---

## 2. Architecture

A three-layer structure: UI, state, and services. External dependencies (Firebase, Agora, STT) are abstracted behind interfaces (`i_*_repository.dart`), so replacing them with an in-house server or a different API later requires no UI changes.

```text
  light source   fingertip       camera          processing      BPM
  ──────────     ──────────────  ──────────────  ──────────────  ──────────
  screen light   blood volume    per-frame       peak detect →   60000
  on the skin    modulates it    brightness log  RR interval     ÷ RR(ms)
```

**Directory layout**

```text
lib/
├── main.dart                       entry point, dark theme, edge-to-edge
├── providers/
│   ├── heart_rate_provider.dart    global BPM state, lifecycle-aware shutdown
│   └── multiplayer_provider.dart
├── services/
│   ├── camera_service.dart         PPG measurement engine
│   ├── ai_voice_service.dart       Gemini + TTS / STT dialogue loop
│   ├── agora_service.dart          voice channel
│   ├── firebase_service.dart       room create / join, opponent BPM sync
│   ├── data_harvesting_service.dart
│   └── repositories/               abstraction interfaces for external services
└── ui/
    ├── screens/                    lobby, pre-check, matching, game, room
    └── widgets/                    PpgLightBar · WaveformPainter · PreCheckModal

predata/                            field debug logs (CSV) collected for PPG tuning
implementation_plan.md              correction algorithm design document
```

---

## 3. Completion Status

**Everything except PPG heart rate measurement is at MVP level.** Because the goal of this cycle was reliable heart rate measurement, the remaining features stop at functional verification.

**PPG heart rate measurement** — primary focus, complete

- Switched to front camera with display illumination and added a custom correction layer on top.
- Stabilized to a usable level; remaining work is handling rapid lighting changes and validating accuracy.

**Single player (vs AI)** — MVP

- The voice dialogue loop runs end to end with Gemini 2.5 Flash plus TTS/STT; the AI starts at 75 BPM and moves according to prompt rules.
- Default TTS/STT packages keep response quality and speed low, and there is no win condition or game rule yet.

**Multiplayer (1:1)** — MVP

- A 6-digit room code is generated; once the opponent joins, both BPM values sync over Firebase RTDB and voice over Agora.
- There is no automatic matching or reconnection recovery, so it assumes code sharing; automatic matching is required before user testing.

**Game system (rules and fun)** — not implemented

- Only the premise exists (raise the heart rate to win); there is no health bar, win condition, round structure, or scoring.
- Actual play showed that the absence of an objective leaves no motivation to play, which is the main open issue from this cycle.

**Data collection pipeline** — MVP

- Background STT during a call captures utterance text and stores it in Firestore together with both players' BPM at that moment.
- This prepares an analysis of which utterances raise heart rate; only collection is implemented, with no analysis logic yet.

**UI / UX** — MVP

- The dark-theme flow from lobby to pre-check, matching, and game is implemented, along with live waveform rendering.
- The text game screen (`text_game_screen.dart`) and room state (`room_provider.dart`) are still empty stubs.

---

## 4. PPG Implementation Process

The principle of camera-based photoplethysmography is simple. Light shone into a fingertip is modulated by the changing blood volume in the capillaries with every heartbeat, so the transmitted light fluctuates slightly. Counting the period of that fluctuation yields the heart rate.

```text
  light source   fingertip       camera          signal processing BPM
  ──────────     ──────────────  ──────────────  ──────────────  ──────────
  screen or flash blood volume   per-frame       peak detection → 60000
  shines light   modulates light brightness log  RR interval     ÷ RR(ms)
```

The difficulty is that this signal is easily corrupted by hand tremor, pressure changes, and lighting changes. The following is the order in which those problems were addressed.

### Stage 1 — Custom algorithm

To be able to debug every step of the measurement, the first implementation computed RGB averages and detected peaks with hand-written code.

It failed. Accuracy was far below usable, and the larger problem was that **there was no way to explain why a value was wrong**. Each spike led to another special case, so the logic grew complex while accuracy did not improve.

### Stage 2 — Field log collection and root cause analysis

Instead of patching by intuition, a CSV logger covering the entire measurement pipeline was added to the app (`CameraService.startLogging()` / `stopAndGetCsv()`).

```text
Timestamp(ms), isGoodSignal, filteredIntensity, rrIntervals_count,
medianRrMs, rawBpm, filteredBpm
```

The key detail is that logging is placed **before the quality-based skip**, so that discarded frames are also recorded — otherwise the cause cannot be identified.

Seven rounds of such measurements are stored in [`predata/`](./predata). Four causes were identified.

1. **Spike noise** — jumps from 85 to 180 BPM within a single frame, a physiologically impossible change.
2. **Staircase drift** — small changes in finger pressure push values up gradually (100 → 105.8 → 112.5), which a spike filter cannot catch.
3. **Grid lock** — because of the 30 FPS (33.33 ms) sampling, noise values settle onto specific numbers such as 112.5 or 180.0, identical down to the decimals.
4. **Limits of `isGoodSignal`** — the package's quality check only evaluates optical stability, so it passes mechanical noise as a valid signal.

One further finding: a rule of "frozen decimals means noise" was considered, but with a very stable posture, valid data also stayed fixed at values like `85.714286` for more than five seconds. Treating zero variance as the sole error criterion would therefore discard valid data as well.

The conclusion was that **software cannot filter out every physical error**. The goal was adjusted from "perfect measurement" to "correction to a usable level."

### Stage 3 — Adopting flutter_ppg and the two-track correction logic

Core peak detection was delegated to the proven `flutter_ppg` package, with a custom correction layer built on top.

All previous special-case handling was discarded, and every situation is now resolved by exactly two criteria (design document: [`implementation_plan.md`](./implementation_plan.md)).

```text
           PPG signal received
                    |
        ┌───────────┴────────────┐
        |                        |
        finger lifted            finger held
        [ TRACK 1 ]              [ TRACK 2 ]
        after 120 frames (4s)    outliers never reset;
        reset completely, then   hold the previous
        return to cold start     value indefinitely
```

**Track 1 — full reset only when the finger is lifted**
Forced resets triggered by internal algorithm state were removed, handing the reset decision to the user's physical action. After 120 frames (about 4 seconds) without a finger, the value resets to 0.0, and on resume the system starts from the same conditions as a fresh app launch, independent of any previous heart rate.

**Track 2 — hold the previous value while the finger stays on**
The comparison baseline was changed from "previous raw value" to "previous filtered value vs. current raw value," which stabilizes the reference. A real heart rate does not change by 20 BPM in 0.03 seconds, so genuine changes are tracked smoothly while clear errors (70 → 200) stay blocked. If the value freezes for too long, the user naturally lifts the finger, which triggers Track 1.

**Correction parameters** (`lib/services/camera_service.dart`)

- **Sample count** — fewer than 3 `rrIntervals` is treated as unreliable; hold the previous value.
- **Central tendency** — arithmetic mean discarded in favor of the median, removing outlier influence.
- **Physiological cutoff** — anything below 40 BPM or above 190 BPM is discarded immediately.
- **Cold start** — accepted as a starting point only when 10 consecutive frames stay within a deviation of 8.0 and the candidate falls between 40 and 100.
- **Spike guard** — a value differing from the previous filtered value by more than 18.0 is ignored and the previous value is held.
- **Smoothing** — EMA with coefficients 0.98 : 0.02 removes fine jitter.
- **Finger-lift detection** — the package keeps `isGoodSignal = true` even after the finger is lifted, so an empty `rrIntervals` is used as the criterion instead.
- **Full reset** — edge-triggered exactly once at 120 bad frames, eliminating CPU load while idle.

### Stage 4 — Limits of the rear camera approach

Once the correction logic settled, the measurement method itself proved to be the problem. The standard approach — finger on the rear camera with the flash on — produces a strong signal thanks to the bright light source, but:

- The flash heats the fingertip very quickly.
- The heat also causes problems for the phone itself.

Heart Attack is not an app that measures for a few seconds; the finger stays in place for an entire round. This was therefore not a tuning issue but a fundamental mismatch of method.

### Stage 5 — Switching to front camera + display illumination

The flash was abandoned as a light source in favor of **using the screen itself as the light source** (current approach).

```text
   [ Stage 4 : rear camera ]        [ Stage 5 : front camera ]

     ┌────────────────┐               ┌────────────────┐
     │                │               │ ██ LIGHT BAR ██│  ← place fingertip
     │                │               │                │
     │                │               │   screen 100%  │
     │                │               │                │
     └────────────────┘               └────────────────┘
        back : lens + flash              front : lens + screen light

     source : physical flash          source : OLED display
     heat   : severe, short use only  heat   : none, long use OK
     light  : immune to ambient       light  : sensitive to ambient change
```

**Implementation**

1. Screen brightness is raised to maximum and the area around the front camera (notch or punch hole) is covered by a pure white light bar. → [`PpgLightBar`](./lib/ui/widgets/ppg_light_bar.dart)
2. `main.dart` enables edge-to-edge mode to remove the translucent scrim Android paints behind the status bar. Without this, the area right next to the lens stays dark and the light output is insufficient.
3. The fingertip is placed on that bar.

**Camera configuration changes**

- Front lens selected, `ResolutionPreset.low` to minimize frame processing load.
- `ExposureMode.auto` — when the finger covers the lens the camera decides the scene is dark and amplifies sensitivity; since the amplified light is only the red light transmitted through skin, the pulse signal becomes clearer.
- `FocusMode.locked` — blocks noise from continuous refocusing while the finger is pressed against the lens.
- All `FlashMode` control code removed, since the front side has no physical flash.

**Results**

- Under fixed lighting conditions, accuracy is higher than with the rear camera approach.
- No heat or device issues even during prolonged contact, which suits a conversation game.
- Without a flash, rapid changes in ambient lighting are hard to handle. This will be addressed by revising the measurement logic.

---

## 5. Next Steps

**Field validation of the front camera approach**
The switch is complete, but no field data has been collected with the front camera yet. The same logging must be run to capture signal degradation patterns, especially under rapidly changing lighting, and the correction logic re-tuned accordingly.

**Accuracy comparison against reference devices such as smartwatches**
Improvements so far were measured by stability (does the value jump?), not accuracy (is the value correct?). Simultaneous measurement with a smartwatch or pulse oximeter should quantify:

- Error at rest, during conversation, and immediately after exercise
- Latency in tracking real changes (the cost of the 0.98 EMA coefficient)
- Variation across devices, skin tones, and lighting conditions

**Alternatives if measurement remains unstable**
New problems keep appearing depending on the environment, so it is worth questioning whether correcting every error is achievable. If a final stabilization pass on the front camera approach still falls short, the following will be considered:

- Switching the game logic to simulated heart rates, or to using only the delta of the measured value
- Restricting the service to smartwatch integration, since most recent models support heart rate broadcasting

**Defining the game rules**
Single- and multiplayer modes are implemented, but the absence of an objective left no motivation to play. Game elements such as a health bar, along with win conditions and round rules, must be designed before user testing.

**Recruiting participants and planning the study**
User testing will begin as soon as the heart rate issue is resolved, but no recruitment plan exists yet; it must be established together with the study design.

---

## 6. Getting Started

```bash
flutter pub get
flutter run
```

A `.env` file is required at the project root (Gemini API key, Agora App ID, and so on). Check the Firebase configuration file (`android/app/google-services.json`) as well.

**How to measure**: raise screen brightness to maximum, then press your index finger firmly against the white light bar at the top of the screen. Measurement is most stable indoors under constant lighting.

---

Capstone Design 2 · 32222962 Junsik Yoon, Dept. of Philosophy / SW Convergence Contents
