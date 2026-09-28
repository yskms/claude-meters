#!/bin/bash
# archive → -exportArchive 済みの .app からDMGを作成し、公証・stapleまで行う。
# 使い方: Distribution/build-dmg.sh <version>  (例: Distribution/build-dmg.sh 0.1.2)
set -euo pipefail

APP_NAME="Claude Meters"
VERSION="${1:?使い方: Distribution/build-dmg.sh <version>}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/ClaudeMeters.xcarchive"
EXPORT_DIR="$ROOT_DIR/dist/export"
EXPORT_APP="$EXPORT_DIR/$APP_NAME.app"
ARCHIVE_APP="$ARCHIVE_DIR/Products/Applications/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/ClaudeMeters-v$VERSION-macOS.dmg"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

if [ ! -d "$EXPORT_APP" ]; then
  echo "エラー: \"$EXPORT_APP\" が見つかりません。先に archive / -exportArchive を実行してください。" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "エラー: create-dmg が見つかりません。'brew install create-dmg' を実行してください。" >&2
  exit 1
fi

create-dmg \
  --volname "$APP_NAME" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 140 160 \
  --app-drop-link 400 160 \
  --hide-extension "$APP_NAME.app" \
  --notarize "claude-meters-notary" \
  --overwrite \
  "$DMG_PATH" \
  "$EXPORT_APP"

echo "DMG作成・公証・staple完了: $DMG_PATH"

# archive/exportの.appはLaunch Servicesに自動登録され、/Applicationsの本体と
# 別アプリとしてSpotlight/Launchpadに重複表示され続ける。DMGができた時点で
# 用済みなので、登録解除してから削除する（再度必要なら archive からやり直せばよい）。
"$LSREGISTER" -u "$EXPORT_APP" 2>/dev/null || true
"$LSREGISTER" -u "$ARCHIVE_APP" 2>/dev/null || true
rm -rf "$EXPORT_DIR" "$ARCHIVE_DIR"
echo "中間生成物(export/archive)を削除しました"
