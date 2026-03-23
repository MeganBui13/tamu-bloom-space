#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_REVISION="$(sed -n 's/^[[:space:]]*revision: "\(.*\)"/\1/p' "$PROJECT_ROOT/.metadata" | head -n 1)"

if [[ -z "${FLUTTER_REVISION}" ]]; then
  echo "Could not determine the Flutter revision from .metadata" >&2
  exit 1
fi

SDK_ROOT="$PROJECT_ROOT/.vercel"
SDK_DIR="$SDK_ROOT/flutter-sdk"

mkdir -p "$SDK_ROOT"

if [[ ! -d "$SDK_DIR/.git" ]]; then
  rm -rf "$SDK_DIR"
  git init "$SDK_DIR" >/dev/null
  git -C "$SDK_DIR" remote add origin https://github.com/flutter/flutter.git
fi

CURRENT_REVISION="$(git -C "$SDK_DIR" rev-parse HEAD 2>/dev/null || true)"

if [[ "$CURRENT_REVISION" != "$FLUTTER_REVISION" ]]; then
  git -C "$SDK_DIR" fetch --depth 1 origin "$FLUTTER_REVISION"
  git -C "$SDK_DIR" checkout --force FETCH_HEAD >/dev/null
fi

export PATH="$SDK_DIR/bin:$PATH"
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true
export PUB_ENVIRONMENT=vercel

flutter config --no-analytics >/dev/null 2>&1 || true
flutter config --enable-web >/dev/null
flutter pub get

BUILD_ARGS=(--release)

if [[ -n "${SUPABASE_URL:-}" ]]; then
  BUILD_ARGS+=("--dart-define=SUPABASE_URL=${SUPABASE_URL}")
fi

if [[ -n "${SUPABASE_ANON_KEY:-}" ]]; then
  BUILD_ARGS+=("--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}")
fi

flutter build web "${BUILD_ARGS[@]}"
