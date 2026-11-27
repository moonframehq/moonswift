#!/usr/bin/env bash
# Benchmark B1's numbers from an xcresult: the median of each metric for the
# Luau list and the SwiftUI one, side by side.
set -euo pipefail
xcrun xcresulttool get test-results metrics --path "${1:-build/bench.xcresult}" | python3 -I -c '
import json, sys
rows = {}
for test in json.load(sys.stdin):
    side = "luau" if "Luau" in test["testIdentifier"] else "swiftui"
    for run in test["testRuns"]:
        for metric in run["metrics"]:
            values = sorted(metric["measurements"])
            rows.setdefault(metric["displayName"], {})[side] = (values[len(values) // 2], metric["unitOfMeasurement"])
print("%-44s %14s %14s   ratio" % ("metric", "luau", "swiftui"))
for name, sides in sorted(rows.items()):
    if "luau" in sides and "swiftui" in sides:
        (luau, unit), (swift, _) = sides["luau"], sides["swiftui"]
        ratio = luau / swift if swift else float("nan")
        print(f"{name:44} {luau:>11.3f} {unit:2} {swift:>11.3f} {unit:2}   ×{ratio:.2f}")
'
