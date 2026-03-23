#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_REVISION="$(sed -n 's/^[[:space:]]*revision: "\(.*\)"/\1/p' "$PROJECT_ROOT/.metadata" | head -n 1)"
FLUTTER_CHANNEL="$(sed -n 's/^[[:space:]]*channel: "\(.*\)"/\1/p' "$PROJECT_ROOT/.metadata" | head -n 1)"

if [[ -z "${FLUTTER_REVISION}" ]]; then
  echo "Could not determine the Flutter revision from .metadata" >&2
  exit 1
fi

if [[ -z "${FLUTTER_CHANNEL}" ]]; then
  FLUTTER_CHANNEL="stable"
fi

SDK_ROOT="$PROJECT_ROOT/.vercel"
SDK_DIR="$SDK_ROOT/flutter-sdk"
SDK_ARCHIVE="$SDK_ROOT/flutter-sdk.tar.xz"
RELEASE_ENV="$SDK_ROOT/flutter-release.env"
RELEASES_JSON="$SDK_ROOT/releases_linux.json"

mkdir -p "$SDK_ROOT"

curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" -o "$RELEASES_JSON"

if command -v node >/dev/null 2>&1; then
  node - "$FLUTTER_REVISION" "$FLUTTER_CHANNEL" "$RELEASE_ENV" "$RELEASES_JSON" <<'NODE'
const fs = require('fs');

const revision = process.argv[2];
const channel = process.argv[3];
const outputPath = process.argv[4];
const manifestPath = process.argv[5];
const data = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

let release = data.releases.find((entry) => entry.hash === revision);

if (!release) {
  const currentHash = data.current_release[channel] || data.current_release.stable;
  release = data.releases.find((entry) => entry.hash === currentHash);
}

if (!release) {
  throw new Error(`Could not resolve a Flutter release for revision ${revision}`);
}

fs.writeFileSync(
  outputPath,
  [
    `FLUTTER_VERSION=${release.version}`,
    `FLUTTER_ARCHIVE=${release.archive}`,
    `FLUTTER_SHA256=${release.sha256}`,
  ].join('\n') + '\n',
);
NODE
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$FLUTTER_REVISION" "$FLUTTER_CHANNEL" "$RELEASE_ENV" "$RELEASES_JSON" <<'PY'
import json
import sys

revision, channel, output_path, manifest_path = sys.argv[1:5]

with open(manifest_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

release = next((entry for entry in data["releases"] if entry.get("hash") == revision), None)

if release is None:
    current_hash = data["current_release"].get(channel) or data["current_release"]["stable"]
    release = next((entry for entry in data["releases"] if entry.get("hash") == current_hash), None)

if release is None:
    raise SystemExit(f"Could not resolve a Flutter release for revision {revision}")

with open(output_path, "w", encoding="utf-8") as handle:
    handle.write(f"FLUTTER_VERSION={release['version']}\n")
    handle.write(f"FLUTTER_ARCHIVE={release['archive']}\n")
    handle.write(f"FLUTTER_SHA256={release['sha256']}\n")
PY
else
  echo "Neither node nor python3 is available to resolve the Flutter release manifest." >&2
  exit 1
fi

source "$RELEASE_ENV"

CURRENT_VERSION="$(cat "$SDK_DIR/version" 2>/dev/null || true)"

if [[ "$CURRENT_VERSION" != "$FLUTTER_VERSION" || ! -x "$SDK_DIR/bin/flutter" ]]; then
  rm -rf "$SDK_DIR" "$SDK_ARCHIVE" "$SDK_ROOT/flutter"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_ARCHIVE}" -o "$SDK_ARCHIVE"
  echo "${FLUTTER_SHA256}  ${SDK_ARCHIVE}" | sha256sum -c -
  tar -xf "$SDK_ARCHIVE" -C "$SDK_ROOT"
  mv "$SDK_ROOT/flutter" "$SDK_DIR"
fi

git config --global --add safe.directory "$SDK_DIR" >/dev/null 2>&1 || true

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
