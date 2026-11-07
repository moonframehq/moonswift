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

# The runtime's tests: mods, reloads, the sandbox.
test:
    swift test --quiet --package-path Packages/MoonKit

# The real app driving itself: clicks, live edits, the sparkle. Leaves pictures
# of the window in build/snapshots.
smoke: build
    rm -rf build/smoke-app build/snapshots
    cp -R app build/smoke-app
    mkdir -p build/snapshots
    # Through LaunchServices, as only that gives the app focus.
    open -n -W --stdout build/snapshots/result.txt --stderr build/snapshots/errors.txt \
        --env MOONSWIFT_APP="$PWD/build/smoke-app" --env MOONSWIFT_SELFDRIVE="$PWD/build/snapshots" "{{app}}"
    cat build/snapshots/result.txt
    grep -q '^all .* passed$' build/snapshots/result.txt

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
        -resultBundlePath build/ios.xcresult CODE_SIGNING_ALLOWED=NO -quiet test

# Prove the App Store build has no live editing in it.
store-audit: generate
    ./scripts/store-audit.sh

lint:
    swiftlint --quiet

# Everything CI should run.
ci: lint check test smoke ios-build store-audit

# Update Luau: bump the version and checksum in the script first.
vendor-luau:
    ./scripts/vendor-luau.sh
