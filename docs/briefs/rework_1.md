# Product Requirements Document (PRD) & AI Specification

## Project Overview

* **Product Concept**: A visual progress reel builder designed to record learning journeys, physical transformations, skills, and personal goals through auto-compiling 1-second daily clips.
* **Tagline / Core Value Proposition**: *"Watch yourself get better, 1 second at a time"* / *"Turn your daily effort into an auto-playing progress reel."*
* **Positioning**: **Visual Reel Builder for Journeys** (Not a habit tracker, not a static photo album, not a plain diary).
* **Core Loop**: Set a Skill Goal → Tap to Capture (1-Second Clip/Photo) → Auto-Stitch into Reel → Interactive Story Scrubbing → Share Progress.
* **Target Use Cases**: Skill progression (tennis, music, coding), physical/fitness transformations, parenting/baby milestones, travel logs.

---

## 1. Minimal Viable Product (MVP) Specifications

The MVP focuses on zero-friction daily logging and immediate visual feedback through automated video compilation.

### Feature 01: Create Journey

* **Description**: Configures a dedicated visual container for tracking a skill or transformation.
* **Data Model Fields**:
* `journey_id` (UUID)
* `user_id` (UUID)
* `title` (String, e.g., *"30 Days of Tennis Forehand"*)
* `category` (Enum: `Skill`, `Fitness`, `Baby`, `Travel`, `Personal`)
* `goal` (String, optional)
* `start_date` (Timestamp)
* `duration_days` (Integer, optional/null for open-ended)



### Feature 02: Daily Reminder & Streak Counter

* **Description**: Time-bound notifications and streak tracking to maximize 24-hour retention.
* **Functionality**:
* Configurable daily push notification per journey.
* Streak engine: Increments when a daily entry is added; computes current, longest, and best streak metrics without blocking main UI threads.



### Feature 03: 1-Tap Daily Record (1-Second Clip Capture)

* **Description**: Zero-friction capture flow engineered to take under 3 seconds to complete.
* **Functionality**:
* In-app camera opens directly to a 1-second video recorder or quick photo snap.
* Video clips auto-trim to **1.0 second** by default (configurable up to 3.0s in settings).
* Optional short note overlay acting as a bottom caption.
* Auto-assigns metadata badge: `"Day X of [Journey Title]"`.


* **Data Model Fields**:
* `record_id` (UUID)
* `journey_id` (UUID, Foreign Key)
* `timestamp` (Timestamp)
* `day_number` (Integer, calculated relative to `start_date`)
* `media_type` (Enum: `Photo`, `Video`)
* `media_url` (String/URI)
* `note` (Text, optional)



### Feature 04: Active Reel Home Feed

* **Description**: Replaces static list cards with live, auto-looping progress video previews.
* **UI/UX Requirements**:
* Each Journey card on the Home dashboard continuously loops a 3-second preview of the latest compiled progress reel.
* Prominent **"+" Record Today** button directly on every card for 1-tap logging.



### Feature 05: Interactive Story Player & Scrubbing Timeline

* **Description**: The primary interface inside a Journey, modeled after mobile video stories.
* **UI/UX Requirements**:
* **Top Half**: Video player with a segmented horizontal story bar (Day 1, Day 2, Day 3...).
* **Live Scrubbing**: Dragging across the story bar seamlessly scrubs through daily 1-second media entries.
* **Bottom Half**: Minimalist timeline feed displaying milestone badges and date notes.



### Feature 06: Milestone Video Chapters

* **Description**: Checkpoints that render as visual badges burned directly into the progress video reel.
* **Data Model Fields**:
* `milestone_id` (UUID)
* `journey_id` (UUID, Foreign Key)
* `title` (String, e.g., *"First Clean Contact"*)
* `day_number` (Integer)
* `badge_style` (String)



### Feature 07: Local FFmpeg Auto-Recap & Social Export Engine

* **Description**: Local media pipeline that automatically compiles daily entries into a unified 9:16 vertical video reel.
* **Functionality**:
* **Aspect Ratio Normalization**: Crops/scales photos and videos to **1080x1920 (9:16)** with blurred background padding for non-standard aspect ratios.
* **Text Burn-in**: Overlays `"Day X"` and optional milestone titles onto the bottom-left corner of each frame.
* **Concatenation**: Uses local device FFmpeg execution to stitch 1-second daily segments sequentially into a single `.mp4` reel file.
* **Social Share Sheet**: Native OS export (`share_plus`) optimized for TikTok, Instagram Reels, and YouTube Shorts.
* **Watermark**: Appends an optional app branding end-card on the free tier.



---

## 2. Post-MVP Roadmap (Phase 2)

Features to build after establishing strong 30-day user retention.

1. **AI Highlight Extractor & Auto-Trimmer**: Multimodal vision AI scans longer video uploads to automatically detect key motion/emotion moments (e.g., impact point of a tennis forehand, a baby's first step) and extracts the best 1-second segment.
2. **AI Audio Sync & Beat Matching**: Automatically syncs daily clip transitions to background music tempos.
3. **AI Narrative Storyteller**: Reads daily entry notes and generates a studio-quality AI voiceover chronicling the entire journey.
4. **Before / After Split Reel**: Generates side-by-side or sliding comparison clips comparing Day 1 directly with Day 30/60/90.
5. **Collaborative Video Reels**: Allows multiple users (e.g., parents or training partners) to contribute daily 1-second clips to a single shared progress reel.

---

## 3. Monetization & Business Logic (Phase 3)

### Pricing Strategy: Freemium

#### Free Tier

* Active Journeys: Maximum 3
* Media Resolution: Standard HD (720p output)
* Export Watermark: Included
* Features: 1-second daily clips, basic story scrubbing, local recap generation

#### Premium Tier ($4.99/month or $39.99/year)

* Unlimited active journeys
* High-Definition video export (1080p / 60fps)
* No app watermark on social exports
* Custom video aspect ratios (9:16, 1:1, 16:9)
* Custom sound track library & AI beat sync
* AI highlight selection & AI voiceover narrative
* Cloud backup & multi-device sync

---

## 4. Technical Architecture & Clean Patterns

* **Frontend**: Flutter or React Native (Cross-platform iOS/Android).
* **Architecture Pattern**: Clean Architecture with strict Repository interfaces (UI components must consume `IJourneyRepository` and `IRecapRepository` to allow painless migration between local SQLite and custom remote backends).
* **Backend & Database**:
* **MVP**: Local SQLite + Supabase (PostgreSQL) for cloud sync and authentication.
* **Media Storage**: Firebase Storage / MinIO / S3 using uniform storage keys (`journeys/<jid>/<recordId>.<ext>`).


* **Media Engine**: Local `FFmpeg` (`ffmpeg_kit_flutter`) for 9:16 frame normalization, text overlay burn-in, and segment concatenation.
* **In-App Purchases**: RevenueCat for cross-platform entitlement checks (`isPremium`).

---