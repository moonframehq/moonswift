derived := "build/DerivedData"
app := derived / "Build/Products/Debug/MoonSwift.app"

default:
    @just --list

# Make MoonSwift.xcodeproj from project.yml.
generate:
    xcodegen generate --quiet

# Open the project in Xcode.
xcode: generate
    open MoonSwift.xcodeproj

# Build the app.
build: generate
    xcodebuild -project MoonSwift.xcodeproj -scheme MoonSwift -configuration Debug \
        -destination 'platform=macOS,arch=arm64' -derivedDataPath {{derived}} -quiet build

# Open the app on this repository's app/, reloading as you save.
run: build
    MOONSWIFT_APP="$PWD/app" "{{app}}/Contents/MacOS/MoonSwift"

# Load every module headlessly and report problems; run after each edit.
check dir="app":
    swift run --quiet --package-path Packages/MoonKit moon check {{dir}}

# Every example app, loaded the same way.
check-examples:
    for example in examples/*/; do just check "$example"; done

# The benchmarks of plans/ios-parity.md, optimized.
bench:
    swift test -c release --quiet --package-path Packages/MoonKit --filter Benchmark 2>&1 | grep -E '^bench |passed|failed'

# The runtime's tests: mods, reloads, the sandbox.
test:
    swift test --quiet --package-path Packages/MoonKit

# The real app driving itself: clicks, live edits, the sparkle, and a scripted
# agent that breaks the app first. Leaves pictures in build/snapshots.
smoke: build
    just _drive --env MOONSWIFT_AGENT="$PWD/scripts/fake-agent.sh"

# The same with the real agent, which spends real tokens.
smoke-agent: build
    just _drive

_drive *extra:
    rm -rf build/smoke-app build/snapshots
    cp -R app build/smoke-app
    mkdir -p build/snapshots
    # Through LaunchServices, as only that gives the app focus.
    open -n -W --stdout build/snapshots/result.txt --stderr build/snapshots/errors.txt \
        --env MOONSWIFT_APP="$PWD/build/smoke-app" --env MOONSWIFT_SELFDRIVE="$PWD/build/snapshots" {{extra}} "{{app}}"
    cat build/snapshots/result.txt
    grep -q '^all .* passed$' build/snapshots/result.txt

# An example app on a simulator, from the beta without its live tools on
# screen, as the store would show it: `just example sheprd`.
example name="sheprd" device="iPhone 17 Pro": ios-build
    xcrun simctl boot "{{device}}" 2>/dev/null || true
    xcrun simctl install "{{device}}" {{derived}}/Build/Products/Debug-iphonesimulator/MoonSwiftBeta.app
    SIMCTL_CHILD_MOONSWIFT_EXAMPLE={{name}} SIMCTL_CHILD_MOONSWIFT_PLAIN=1 \
        xcrun simctl launch --terminate-running-process "{{device}}" dev.moonswift.ios.beta

# Both iOS apps, for the simulator.
ios-build: generate
    xcodebuild -project MoonSwift.xcodeproj -scheme MoonSwiftStore -configuration Debug \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath {{derived}} -quiet build
    xcodebuild -project MoonSwift.xcodeproj -scheme MoonSwiftBeta -configuration Debug \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath {{derived}} -quiet build

# The beta on a simulator, with real taps. Pass another simulator's name to
# use it; slow to start, so it's not part of `just ci`.
ios-test device="iPhone 17": generate
    rm -rf build/ios.xcresult
    xcodebuild -project MoonSwift.xcodeproj -scheme MoonSwiftBeta -configuration Debug \
        -destination 'platform=iOS Simulator,name={{device}}' -derivedDataPath {{derived}} \
        -resultBundlePath build/ios.xcresult CODE_SIGNING_ALLOWED=NO -quiet \
        -skip-testing:MoonSwiftBetaUITests/BenchTests test

# Benchmark B1: flick 10k rows drawn by Luau and by SwiftUI, and compare
# their hitches. On a simulator the numbers only compare; on a device they
# are the real ones.
ios-bench device="iPhone 17 Pro": generate
    rm -rf build/bench.xcresult
    xcodebuild -project MoonSwift.xcodeproj -scheme MoonSwiftBeta -configuration Release \
        -destination 'platform=iOS Simulator,name={{device}}' -derivedDataPath {{derived}} \
        -resultBundlePath build/bench.xcresult CODE_SIGNING_ALLOWED=NO -quiet \
        -only-testing:MoonSwiftBetaUITests/BenchTests test
    ./scripts/bench-report.sh build/bench.xcresult

# Prove the App Store build has no live editing in it.
store-audit: generate
    ./scripts/store-audit.sh

lint:
    swiftlint --quiet

# Everything CI should run.
ci: lint check check-examples test smoke ios-build store-audit

# Update Luau: bump the version and checksum in the script first.
vendor-luau:
    ./scripts/vendor-luau.sh

# Copy the conformance suite from a Moonframe checkout, the reference copy.
conformance-sync moonframe="~/code/moonframe":
    rsync -a --delete {{moonframe}}/conformance/ conformance/

# Copy Moonframe's components into MoonKit's library, which every app can
# `use`; the gallery test then draws each one.
components-sync moonframe="~/code/moonframe":
    rsync -a --delete --include='*.luau' --exclude='*' {{moonframe}}/app/components/ Packages/MoonKit/Sources/MoonKit/Library/components/
