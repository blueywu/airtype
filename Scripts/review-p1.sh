#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
review_output="${1:-$PWD/dist/p1-review}"
mkdir -p "$review_output"
review_output="${review_output:A}"
review_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[[ -d "$review_sdk" ]] || review_sdk="$(xcrun --show-sdk-path)"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
review_flags=(--disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --build-system native --sdk "$review_sdk")
swift build -c debug "${review_flags[@]}" > "$review_output/debug-build.log" 2>&1
for review_test in voice-actions voice-session shortcut audio-lifecycle; do
  .build/debug/vRemote "--${review_test}-self-test" > "$review_output/${review_test}-tests.log" 2>&1
  print "PASS $review_test"
done
./package-app.sh "${review_flags[@]}" > "$review_output/release-build.log" 2>&1
mkdir -p dist/review
ditto dist/build/AirType.app dist/review/AirType.app
cp .build/debug/vRemote dist/review/AirType.app/Contents/MacOS/vRemote
codesign --force --deep --sign - --timestamp=none dist/review/AirType.app
python3 Scripts/capture-p1.py --app dist/review/AirType.app --output "$review_output"
print "Review ready: $review_output"
