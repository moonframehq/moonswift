#!/usr/bin/env bash
# App Review guideline 2.5.19 bans dormant features, so live editing has to be
# absent from a store binary, not just switched off. Fails if a trace of it
# is in the Release store build, and also if none is in the beta build: an
# audit that can't see the feature there proves nothing.
set -euo pipefail

derived="build/DerivedData"
# Long ones only: Swift keeps strings of up to 15 bytes inside the machine
# code, where `strings` can't see them, even in a build that has them.
markers=(
    "MoonLive"
    "applies as you type"
    "Showing the last good version."
    "Point at anything to see what drew it"
    "Copy this element for an agent"
)

build() {
    xcodebuild -project MoonSwift.xcodeproj -scheme "$1" -configuration Release \
        -destination 'generic/platform=iOS' -derivedDataPath "$derived" \
        CODE_SIGNING_ALLOWED=NO -quiet build
}

traces() {
    local binary="$derived/Build/Products/Release-iphoneos/$1.app/$1" found=0 text
    # Through a file: piped into `grep -q`, `strings` dies of SIGPIPE on the
    # first match, pipefail calls that a miss, and a dirty build looks clean.
    text="$(mktemp)"
    strings -a "$binary" > "$text"
    for marker in "${markers[@]}"; do
        if grep -qF "$marker" "$text"; then
            echo "  $1 contains: $marker" >&2
            found=$((found + 1))
        fi
    done
    rm -f "$text"
    echo "$found"
}

build MoonSwiftStore
build MoonSwiftBeta

store="$(traces MoonSwiftStore)"
beta="$(traces MoonSwiftBeta 2>/dev/null)"

if [ "$beta" -ne "${#markers[@]}" ]; then
    echo "✘ the audit sees only $beta of ${#markers[@]} markers in the beta build, so it can't be trusted"
    exit 1
fi
if [ "$store" -ne 0 ]; then
    echo "✘ the store build contains live editing"
    exit 1
fi
echo "✔ store build is clean: 0 of ${#markers[@]} markers, against $beta of ${#markers[@]} in the beta"
