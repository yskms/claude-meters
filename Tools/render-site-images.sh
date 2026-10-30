#!/bin/bash
# Regenerates public/images/ (the introduction site's popover and menu bar
# images) by rendering the app's own views with sample values. Run it after
# changing the UI. See "紹介サイト" in CLAUDE.md.
#
#   Tools/render-site-images.sh
#
# Needs Xcode and XcodeGen. Uses a throwaway DerivedData and ad-hoc signing,
# so it touches neither your signing setup nor the app's real preferences.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

out="$PWD/public/images"
derived="$(mktemp -d)"
trap 'rm -rf "$derived"' EXIT
mkdir -p "$out"

xcodegen generate >/dev/null

for lang in en ja; do
  # TEST_RUNNER_ prefix: xcodebuild passes these to the test process, without the prefix.
  TEST_RUNNER_SITE_IMAGES_DIR="$out" TEST_RUNNER_SITE_IMAGES_LANG="$lang" \
  nice -n 10 xcodebuild -project ClaudeMeters.xcodeproj -scheme ClaudeMeters \
    -destination "platform=macOS" -derivedDataPath "$derived" \
    -only-testing:ClaudeMetersTests/SiteImageRenderTests -testLanguage "$lang" \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" test 2>&1 \
    | grep -E "^Test Case .*(passed|failed|skipped)|^\*\* TEST|: error:" || true
done

ls -l "$out"
