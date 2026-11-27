#!/usr/bin/env bash
# Benchmark B6: Sheprd's Pull Requests tab drawn by SwiftUI and by Luau, on
# a simulator, as sheprd-labs/sheprd#1715 measures it. Builds the beta
# optimized, then runs each engine in a fresh launch, alternating, RUNS
# times, and prints the medians. See MoonSwift/Examples/PullRequestsBench.swift.
#
#   scripts/prs-bench.sh [SIMULATOR] [RUNS]
set -euo pipefail

device=${1:-iPhone 17 Pro}
runs=${2:-5}
bundle=dev.moonswift.ios.beta
derived=build/DerivedData
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project MoonSwift.xcodeproj -scheme MoonSwiftBeta -configuration Release \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO -quiet build
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl install "$device" "$derived/Build/Products/Release-iphonesimulator/MoonSwiftBeta.app"

out=$(mktemp -d /tmp/prs-bench.XXXXXX)
for i in $(seq 1 "$runs"); do
    for engine in swiftui luau; do
        xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
        data=$(xcrun simctl get_app_container "$device" "$bundle" data)
        rm -f "$data/Documents/prs-bench.json"
        SIMCTL_CHILD_MOONSWIFT_BENCH="prs-$engine" xcrun simctl launch "$device" "$bundle" >/dev/null
        waited=0
        until [ -f "$data/Documents/prs-bench.json" ] || [ "$waited" -ge 90 ]; do
            sleep 1
            waited=$((waited + 1))
        done
        cp "$data/Documents/prs-bench.json" "$out/$engine-$i.json"
        echo "$engine $i: $(cat "$out/$engine-$i.json")"
    done
done
xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true

python3 -I - "$out" <<'EOF'
import json, pathlib, statistics, sys
runs = {}
for path in sorted(pathlib.Path(sys.argv[1]).glob("*.json")):
    run = json.loads(path.read_text())
    runs.setdefault(run["engine"], []).append(run)
metrics = [
    ("firstFrameMs", "Tab open to first frame with rows, ms"),
    ("hitchMsPerS", "Hitch time while scrolling, ms/s"),
    ("hitches", "Hitched frames per run"),
    ("frames", "Frames per run"),
    ("mainCPUMsPerS", "Main thread CPU while scrolling, ms/s"),
    ("medianFrameMs", "Median frame, ms"),
    ("worstFrameMs", "Worst frame, ms"),
    ("footprintBeforeMB", "Memory before the tab, MB"),
    ("footprintShownMB", "Memory with the tab shown, MB"),
    ("footprintAfterScrollMB", "Memory after scrolling, MB"),
]
hz = runs["swiftui"][0]["maxFramesPerSecond"]
print(f"\n{len(runs['swiftui'])} runs each, median; {hz:.0f} Hz screen\n")
print("| Metric | SwiftUI | Luau |\n| --- | ---: | ---: |")
for key, title in metrics:
    swift = statistics.median(r[key] for r in runs["swiftui"])
    luau = statistics.median(r[key] for r in runs["luau"])
    print(f"| {title} | {swift:.1f} | {luau:.1f} |")
EOF
