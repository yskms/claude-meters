#!/bin/bash
# Regenerates public/images/ (the introduction site's popover and menu bar
# images) by rendering the app's own views with sample values. Run it after
# changing the UI. See "紹介サイト" in CLAUDE.md.
#
#   Tools/render-site-images.sh
#
# Needs Xcode and XcodeGen. Uses a throwaway DerivedData and ad-hoc signing,
# so it touches neither your signing setup nor the app's real preferences.
#
# Fails (non-zero) if xcodebuild fails, if the render test is skipped (the
# environment variables did not reach it), or if any expected image was not
# rewritten by this run, so old images can never pass as freshly rendered.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

out="$PWD/public/images"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

xcodegen generate >/dev/null

touch "$work/started"

for lang in en ja; do
  log="$work/test-$lang.log"
  # TEST_RUNNER_ prefix: xcodebuild passes these to the test process, without the prefix.
  if ! TEST_RUNNER_SITE_IMAGES_DIR="$out" TEST_RUNNER_SITE_IMAGES_LANG="$lang" \
       nice -n 10 xcodebuild -project ClaudeMeters.xcodeproj -scheme ClaudeMeters \
         -destination "platform=macOS" -derivedDataPath "$work/derived" \
         -only-testing:ClaudeMetersTests/SiteImageRenderTests -testLanguage "$lang" \
         CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" test \
         >"$log" 2>&1; then
    echo "xcodebuild failed ($lang). Last lines of its output:" >&2
    tail -n 40 "$log" >&2
    exit 1
  fi
  grep -E "^Test Case .*(passed|failed|skipped)|^\*\* TEST|: error:" "$log" || true
  if grep -q "^Test Case .*skipped" "$log"; then
    echo "The render test was skipped ($lang): SITE_IMAGES_DIR did not reach it, so nothing was rendered." >&2
    exit 1
  fi
done

expected=(glyph-black glyph-white popover-en-light popover-en-dark popover-ja-light popover-ja-dark)
for name in "${expected[@]}"; do
  if [ ! -f "$out/$name.png" ] || [ ! "$out/$name.png" -nt "$work/started" ]; then
    echo "Not rewritten by this run: public/images/$name.png" >&2
    exit 1
  fi
done

ls -l "$out"
