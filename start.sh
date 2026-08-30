#!/usr/bin/env bash
# Behang — one-command start: media storage (Docker), backend rules, app.
set -uo pipefail
cd "$(dirname "$0")"

echo "==> Opening iOS Simulator"
open -a Simulator

echo "==> Starting local media storage (MinIO + presign service)"
if command -v docker >/dev/null 2>&1; then
  if docker compose -f infra/docker-compose.yml up -d --build; then
    echo "==> Media storage up (http://localhost:9000, console :9001)."
  else
    echo "!! Media storage failed to start — media uploads won't work."
  fi
else
  echo "!! Docker not found — skipping media storage."
fi

if command -v firebase >/dev/null 2>&1; then
  echo "==> Deploying Firestore rules (needs the console setup done once)"
  if firebase deploy --project behangapp --only firestore:rules; then
    echo "==> Rules deployed — cloud mode active."
  else
    echo "!! Deploy failed. The app still runs in offline mode; do the console setup"
    echo "   (Auth > Email/Password, Firestore > Create), then rerun ./start.sh"
  fi
else
  echo "!! Firebase CLI not found — skipping rules deploy."
fi

echo "==> Launching the app (r = hot reload, q = quit)"
flutter run \
  --dart-define=MEDIA_STORE=minio \
  --dart-define=UPLOAD_API=http://localhost:9010