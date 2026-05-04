# Social Mirror

An iOS app that records or imports a conversation, runs **fully on-device speaker diarization** with an ECAPA-TDNN Core ML model, and produces a "Social X-ray" coaching report — talk-time balance, dominance, confidence, and a short actionable tip.

**Zero cloud. Zero audio storage by default. All ML runs locally.**

## What it does

- Capture live audio (or import an `.m4a` / `.mp3` / `.wav` / `.aac` / `.opus` file from Files or Voice Memos, up to 3 hours)
- Voice-activity detection → speech segmentation
- 80-bin log-mel filterbank feature extraction (Accelerate / vDSP)
- Speaker embeddings via on-device **ECAPA-TDNN** Core ML model (192-dim, Float16)
- Online cosine clustering + post-session agglomerative refinement
- Per-speaker pitch (vDSP normalized autocorrelation), energy, turn count, talk-time ratio
- Rules-based dominance + confidence scoring
- Coaching report: headline, insight, actionable tip
- Encrypted Core Data persistence (`completeUnlessOpen`); audio storage is opt-in

## Stack

- **Swift 5.9+**, **SwiftUI**, iOS 17+ (current deployment target: iOS 26.2)
- **Xcode 26** with file-system-synchronized groups
- **AVFoundation** (capture, file I/O, resample to 16 kHz mono Float32)
- **Accelerate / vDSP** (FFT, mel matrix, autocorrelation pitch)
- **Core ML** (ECAPA-TDNN, Float16 throughout)
- **Core Data** (encrypted at rest)
- **Swift Testing** (`@Test`, `@Suite(.serialized)`)
- **OSSignposter** for Instruments tracing of the inference path

## Architecture

```
SocialMirror/
├── App/             @main entry, root NavigationStack
├── Audio/           AVAudioEngine pipeline + VAD + segment buffer + coordinator
├── ML/              CoreMLSpeakerEmbedder, mock embedder, cosine clusterer, DiarizationEngine
├── Features/        feature extraction, dominance, coaching, SessionAnalyzer
├── Storage/         CoreDataStack + AudioStorageManager (encrypted)
├── Models/          Codable Swift structs mirroring CoreData entities
├── Views/           all SwiftUI views + RadarChart (Canvas)
├── ViewModels/      LiveSessionStore, ImportSessionViewModel
├── Utils/           DesignSystem, SpeakerColor, DiarizationConfig, Constants
└── SocialMirror.xcdatamodeld/   Core Data schema
```

The diarization stack is parameterized per `SessionType`. Defaults are tuned for one-on-one calls / interviews / negotiations (10s segment cap, 0.75 cosine threshold). `SessionType.podcast` and `SessionType.meeting` use a tighter 2s cap + 0.65 threshold so short turns from multiple speakers don't get glued together.

## Build & test

```bash
# Build for simulator (no signing)
xcodebuild -project SocialMirror.xcodeproj -scheme SocialMirror \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Run unit tests on iPhone 17
xcodebuild -project SocialMirror.xcodeproj -scheme SocialMirror \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -only-testing:SocialMirrorTests test CODE_SIGNING_ALLOWED=NO
```

## Privacy

- Microphone audio is processed in-process; nothing is sent off-device.
- Audio file storage is **off by default** and configurable in Settings; when on, files are written with `completeUnlessOpen` protection.
- Core Data store uses `completeUnlessOpen` file protection.
- The bundled ECAPA Core ML model runs through `MLComputeUnits.all` (Neural Engine when available).

## Status

| Component | State |
|---|---|
| Audio capture, VAD, segmentation, RMS | Real |
| 80-bin log-mel front-end (vDSP) | Real |
| ECAPA-TDNN speaker embeddings (Core ML) | **Real** — bundled `ECAPA.mlpackage`, Float16 in/out |
| Online clustering + post-session refinement | Real |
| Acoustic features (pitch / energy / variance) | Real |
| Coaching rules engine | Real |
| Core Data persistence (encrypted) | Real |
| Audio file storage (encrypted, opt-in) | Real |
| Speech transcription (SFSpeechRecognizer) | Not yet — `transcript: []` is empty so hedge / question / word counts are zero |
| HealthKit (sleep / HRV correlation) | Not yet |

## License

Personal project. All rights reserved.
