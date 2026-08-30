# Behang

*A visual journal for your journey* — turn your everyday moments into a story.

Behang is a cross-platform (iOS & Android) visual journaling app for capturing daily milestones and emotional progress over time. Set a goal, show up daily, capture a moment, and watch your story build itself.

## Features (MVP)

| # | Feature | Description |
|---|---------|-------------|
| 1 | **Create Journey** | Tracking container for any goal: category (Baby / Fitness / Skill / Travel / Personal / Other), optional goal text, start date, duration (or open-ended). |
| 2 | **Daily Reminder & Streak Counter** | Configurable per-journey daily push notification time. Streak increments for consecutive days with a record; best streak is tracked too. |
| 3 | **Daily Record** | Capture photo, video, or note per day. |
| 4 | **Interactive Calendar** | Month grid rendering each day's media thumbnail, decorative emoji stickers (long-press a day), and achievement badge overlays. |
| 5 | **Visual Timeline** | Chronological feed of all moments grouped by month, with inline video playback and full-screen photo viewer. |
| 6 | **Custom Milestones** | User-defined checkpoints with badge emoji, optional target date, achieved date → badges appear on the calendar. |
| 7 | **Recap Slideshow** | Auto-playing recap of a journey's photos with day captions ("Day 12 · August 23"). |

## Tech Stack

- **Flutter** (Material 3) — single codebase for iOS & Android
- **SQLite** (`sqflite`) — offline/local mode storage
- **Firebase** — Auth (email/password), Firestore (realtime journeys)
- **MinIO** (Docker, dev) / **Firebase Storage** (production) — shared media
- **Provider** — state management
- **flutter_local_notifications** — scheduled daily reminders
- **image_picker** / **video_player** — media capture & playback

The app runs in two modes, selected automatically at startup:

| Mode | When | What works |
|------|------|-----------|
| ☁️ Cloud | `GoogleService-Info.plist` / `google-services.json` present (via `flutterfire configure`) | Accounts, invites, shared journeys, realtime sync, watch-together recaps |
| 📴 Offline | No Firebase config found | Single-user journal stored on-device |

Both modes share one UI through a `Backend` abstraction (`lib/core/backend/`).

### Media storage (two interchangeable backends)

Photos & videos go through a `MediaStore` interface — keys are identical for both, so switching is one line:

- **MinIO via Docker** (default dev setup): `infra/` runs MinIO + a tiny presign service. No paid Firebase plan needed. Enabled with `--dart-define=MEDIA_STORE=minio --dart-define=UPLOAD_API=http://localhost:9010`.
- **Firebase Storage**: needs the **Blaze** (pay-as-you-go) plan. This is `MEDIA_STORE=firebase` (the default) — just drop the dart-defines when you upgrade.

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x)
- Xcode (for iOS) and/or Android Studio (for Android)

### Run it (recommended)

```bash
./start.sh
```

Starts the simulator, brings up the MinIO media stack, deploys Firestore rules, and launches the app in cloud mode.

Manual equivalent:

```bash
docker compose -f infra/docker-compose.yml up -d --build   # media storage
firebase deploy --project behangapp --only firestore.rules # cloud data access
open -a Simulator
flutter run --dart-define=MEDIA_STORE=minio --dart-define=UPLOAD_API=http://localhost:9010

# Android emulator/device (no docker media on device yet)
flutter run
```

> Camera capture requires a physical device — use "Choose photo/video" in the simulator.

### Tests & analysis

```bash
flutter analyze
flutter test
```

## Collaborative Journeys (Firebase)

Inspired by shared journaling: one goal, multiple people, memories and recaps together.

- **Invite** — open a journey → "Invite" → share the 6-character code with your partner/friend.
- **Join** — they tap the 🔗 icon on Home, enter the code, and instantly see the journey sync live.
- **Shared memories** — every moment shows who captured it; media uploads to Cloud Storage automatically.
- **Catch up 📬** — a banner on top of a journey shows new moments added by others since your last visit.
- **Watch together 🎬** — during a recap, tap the groups button: everyone in the journey follows the same slide, driven by whoever plays it.

### One-time Firebase setup

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Then in the [Firebase console](https://console.firebase.google.com):

1. **Authentication** → Sign-in method → enable **Email/Password**.
2. **Firestore Database** → Create database.
3. **Storage** → Get started.

Restart the app — it detects the config and switches to cloud mode automatically.

## Project Structure

```
lib/
├── main.dart                 # App bootstrap
├── app.dart                  # MaterialApp + theme wiring
├── app_state.dart            # Global store (ChangeNotifier + repositories)
├── core/
│   ├── backend/              # Backend abstraction: LocalBackend ↔ CloudBackend (Firebase)
│   ├── db/app_database.dart  # SQLite schema (offline mode + local cache)
│   ├── models/               # Journey, RecordEntry, Milestone, DaySticker, Member, Profile
│   ├── repos/                # Local repositories used by LocalBackend
│   ├── services/             # Streak engine, notifications, media, theme
│   └── utils/
├── features/
│   ├── journeys/             # List, create, detail, invite & join flows
│   ├── profile/              # Sign-in / profile sheet
│   ├── records/              # Capture screen
│   └── recap/                # Recap player with watch-together sync
└── widgets/                  # Calendar grid, timeline, thumbnails, video player
```

## Roadmap

- **Phase 2**: AI story generator, before/after comparison, AI auto-tagging, weekly recaps, journey sharing, collaborative journeys.
- **Phase 3**: Freemium tiers, premium templates, HD export, cloud sync, photobook print-on-demand.

See [`docs/briefs/brief.md`](docs/briefs/brief.md) for the full product requirements document.
