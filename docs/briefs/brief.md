# Product Requirements Document (PRD) & AI Specification

## Project Overview

* **Product Concept**: A visual journaling mobile application centered around capturing daily milestones and emotional progress over time.
* **Tagline / Core Value Proposition**: *"Turn your everyday moments into a story"* / *"A visual journal for your journey."*
* **Core User Question**: *"What did they do for the first time today?"*
* **Core Loop**: Set a Goal → Show Up → Capture a Moment → Build Timeline → Track Progress → Create Story
* **Target Use Cases**: Skill progression (e.g., learning tennis or an instrument), parenting/baby tracking, travel logs, fitness transformations, personal milestones.

---

## 1. Minimal Viable Product (MVP) Specifications

The MVP focuses exclusively on validating product-market fit (PMF) through core retention features.

### Feature 01: Create Journey

* **Description**: User creates a tracking container for a specific goal or event.
* **Data Model Fields**:
* `journey_id` (UUID)
* `user_id` (UUID)
* `title` (String, required)
* `category` (Enum: `Baby`, `Fitness`, `Skill`, `Travel`, `Personal`, `Other`)
* `goal` (String, optional)
* `start_date` (Timestamp)
* `duration_days` (Integer, optional/null for open-ended)



### Feature 02: Daily Reminder & Streak Counter

* **Description**: Push notification trigger to encourage daily entries and a visual gamified streak counter.
* **Functionality**:
* Configurable daily push notification time per journey.
* Streak calculation engine: Increments if a record is added within the 24-hour window; resets or pauses based on streak rules.



### Feature 03: Daily Record

* **Description**: Main entry point for capturing moments.
* **Data Model Fields**:
* `record_id` (UUID)
* `journey_id` (UUID, Foreign Key)
* `timestamp` (Timestamp)
* `media_type` (Enum: `Photo`, `Video`, `None`)
* `media_url` (String/URI, optional)
* `note` (Text, optional)



### Feature 04: Interactive Calendar View

* **Description**: Monthly calendar grid displaying individual journey progress.
* **UI/UX Requirements**:
* Daily grid cell renders a visual media thumbnail of that day's entry.
* Overlay capability for decorative stickers or achievement badges on specific calendar dates.



### Feature 05: Visual Timeline

* **Description**: Chronological feed of all recorded moments.
* **UI/UX Requirements**:
* Vertical or horizontal scrolling timeline displaying photos, videos, and notes ordered by timestamp.



### Feature 06: Custom Milestones

* **Description**: User-defined checkpoint markers within a journey.
* **Data Model Fields**:
* `milestone_id` (UUID)
* `journey_id` (UUID, Foreign Key)
* `title` (String)
* `target_date` (Timestamp, optional)
* `achieved_at` (Timestamp, optional)
* `badge_icon` (String)



### Feature 07: Auto Recap Video Generator

* **Description**: End-of-journey or periodic media compiler.
* **Functionality**:
* Compiles uploaded daily photos and short video clips into a single consolidated slideshow/video output.



---

## 2. Post-MVP Roadmap (Phase 2)

Features to be built after establishing baseline user retention.

1. **AI Story Generator**: Uses LLM prompts to analyze notes and compile a textual narrative story of the journey.
2. **Before / After Comparison**: Side-by-side visual comparison tool for physical or skill transformations.
3. **AI Auto-Tagging**: Computer vision engine to automatically tag media content (e.g., `first-step`, `beach`, `smile`).
4. **Weekly Recap**: Automated visual and textual mini-summaries generated every 7 days.
5. **Journey Sharing & Public Profiles**: Web view links and public user profiles to showcase completed journeys.
6. **Collaborative Journeys**: Multi-user editing permissions for shared events (e.g., parents contributing to *"Baby's First Year"*, friends sharing *"Japan Trip"*).

---

## 3. Monetization & Business Logic (Phase 3)

### Pricing Strategy: Freemium

#### Free Tier Limits

* Active Journeys: Maximum 3
* Media Support: Standard photo uploads
* Features: Basic Calendar, Basic Timeline, Standard Recap generation

#### Premium Tier ($4.99/month or $39.99/year)

* Unlimited active journeys
* High-definition video upload & storage
* AI Story generation & AI Auto-tagging
* Premium recap templates without watermark
* HD video export
* Expanded sticker library
* Cloud sync & multi-device backup
* Collaborative multi-user journeys

#### Extended Physical Monetization

* Photobook generation API (print-on-demand integration for baby books, yearbooks, travel albums, and printed calendars).

---

## 4. Suggested Technical Architecture

* **Frontend**: Flutter or React Native (Cross-platform iOS/Android)
* **Backend & Database**: Firebase (Auth, Firestore DB, Cloud Storage, Push Notifications) or Supabase
* **Media Processing**: FFmpeg (Local/Serverless video compilation)
* **In-App Purchases**: RevenueCat
* **AI Integrations**: OpenAI API / Gemini Flash API (via Serverless Functions)