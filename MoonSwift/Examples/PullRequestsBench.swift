#if os(iOS)
import Darwin
import MoonKit
import MoonUI
import QuartzCore
import SwiftUI
import UIKit

/// Benchmark B2: Sheprd's Pull Requests tab, drawn by Luau (`examples/prs`)
/// and by SwiftUI (`PullRequestsList`), measured as sheprd-labs/sheprd#1715
/// measures it. After launch settles, it opens the tab, times the first
/// frame with rows, then scrolls end to end 4 times at 3000 pt/s timing
/// every frame; a hitch is a frame over 1.5× its target. Results go to the
/// log and to `Documents/prs-bench.json`; `just prs-bench` runs both.
struct PullRequestsBench: View {
    /// `swiftui` or `luau`.
    let engine: String

    @State private var open = false

    var body: some View {
        NavigationStack {
            if open {
                if engine == "luau" { LuauPullRequests() } else { PullRequestsList() }
            } else {
                Text(verbatim: "Home")
            }
        }
        .task { await run() }
    }

    private func run() async {
        // Lets launch settle, as on Sheprd's Home.
        try? await Task.sleep(for: .seconds(3))
        let before = Self.footprint()
        let opened = CACurrentMediaTime()
        open = true
        let frames = FrameClock()
        let firstFrame = await frames.first { Self.list()?.visibleCells.count ?? 0 >= 3 }
        try? await Task.sleep(for: .seconds(1))
        let shown = Self.footprint()
        guard let list = Self.list() else { return Self.report(["engine": engine, "error": "no list"]) }
        let revision = LuauPullRequests.workspace?.revision ?? 0
        let cpu = Self.mainThreadCPU()
        let scroll = await frames.scroll(list, passes: 4, pointsPerSecond: 3000)
        let busy = (Self.mainThreadCPU() - cpu) * 1000 / max(scroll.seconds, 1)
        Self.report([
            "engine": engine,
            "firstFrameMs": (firstFrame - opened) * 1000,
            "footprintBeforeMB": before, "footprintShownMB": shown, "footprintAfterScrollMB": Self.footprint(),
            "maxFramesPerSecond": Double(list.window?.windowScene?.screen.maximumFramesPerSecond ?? 0),
            "frames": Double(scroll.frames), "hitches": Double(scroll.hitches),
            "hitchMsPerS": scroll.hitchRatio, "worstFrameMs": scroll.worst * 1000,
            "luauLoadMs": LuauPullRequests.loadSeconds * 1000, "mainCPUMsPerS": busy,
            "redraws": (LuauPullRequests.workspace?.revision ?? 0) - revision,
            "medianFrameMs": scroll.median * 1000, "seconds": scroll.seconds, "hitchesByPass": scroll.byPass, "hitchesAt": scroll.at,
        ])
    }

    /// The tab's list: the largest collection view on screen.
    private static func list() -> UICollectionView? {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        var found: [UICollectionView] = []
        func walk(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0 else { return }
            if let list = view as? UICollectionView { found.append(list) }
            view.subviews.forEach(walk)
        }
        window.map(walk)
        return found.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// CPU time the main thread has used, in seconds: the bench runs on it,
    /// so this is what scrolling cost, steadier than hitches on a busy Mac.
    private static func mainThreadCPU() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    /// The app's memory as the system counts it, in megabytes.
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    private static func report(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        print("PRS_BENCH \(String(decoding: data, as: UTF8.self))")
        try? data.write(to: URL.documentsDirectory.appending(path: "prs-bench.json"))
    }
}

/// The tab in Luau, as Sheprd hosts it: its workspace made on the first
/// draw, so the first frame pays for loading the Luau.
private struct LuauPullRequests: View {
    @State private var workspace: Workspace?

    var body: some View {
        let workspace = workspace ?? Self.load()
        MoonCanvas()
            .environment(workspace)
            .navigationDestination(for: LuauValue.self) { Text(verbatim: $0.summary) }
            .onAppear { self.workspace = workspace }
    }

    /// How long loading the Luau took, for the report.
    static var loadSeconds: Double = 0
    /// The workspace, to count its redraws while scrolling.
    static weak var workspace: Workspace?

    private static func load() -> Workspace {
        let start = CACurrentMediaTime()
        defer { loadSeconds = CACurrentMediaTime() - start }
        let folder = Bundle.main.url(forResource: "examples/prs", withExtension: nil)
            ?? Bundle.main.bundleURL.appending(path: "examples/prs")
        let workspace = Workspace(folders: Folders(builtin: folder))
        workspace.reload()
        Self.workspace = workspace
        return workspace
    }
}

/// A display link asking for the screen's full rate, timing each frame.
@MainActor
private final class FrameClock: NSObject {
    struct Scroll {
        var frames = 0, hitches = 0
        /// Hitches in each half pass, down then up: where they cluster.
        var byPass: [Int] = []
        /// Where each hitch happened: the offset, as a share of the way down.
        var at: [Int] = []
        var hitchTime: CFTimeInterval = 0, worst: CFTimeInterval = 0, median: CFTimeInterval = 0, seconds: CFTimeInterval = 0
        /// Milliseconds of hitch per second of scrolling, as Instruments counts it.
        var hitchRatio: Double { seconds > 0 ? hitchTime * 1000 / seconds : 0 }
    }

    private var tick: ((CADisplayLink) -> Bool)?
    private var done: CheckedContinuation<Void, Never>?

    /// The time of the first frame at which `ready` holds.
    func first(where ready: @escaping () -> Bool) async -> CFTimeInterval {
        var at: CFTimeInterval = 0
        await run { link in
            guard ready() else { return false }
            at = link.timestamp
            return true
        }
        return at
    }

    /// Scrolls `list` to its end and back `passes` times at a steady speed.
    func scroll(_ list: UICollectionView, passes: Int, pointsPerSecond: CGFloat) async -> Scroll {
        var result = Scroll()
        var intervals: [CFTimeInterval] = []
        var last: CFTimeInterval?
        var down = true, turns = 0
        let top = -list.adjustedContentInset.top
        await run { link in
            let expected = link.targetTimestamp - link.timestamp
            if let last {
                let interval = link.timestamp - last
                intervals.append(interval)
                result.seconds += interval
                result.worst = max(result.worst, interval)
                if interval > expected * 1.5 {
                    result.hitches += 1
                    while result.byPass.count <= turns { result.byPass.append(0) }
                    result.byPass[turns] += 1
                    let range = list.contentSize.height - list.bounds.height
                    result.at.append(range > 0 ? Int((list.contentOffset.y + list.adjustedContentInset.top) / range * 100) : 0)
                    result.hitchTime += interval - expected
                }
                let bottom = max(top, list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height)
                var y = list.contentOffset.y + (down ? 1 : -1) * pointsPerSecond * CGFloat(interval)
                if y >= bottom || y <= top {
                    y = min(max(y, top), bottom)
                    down.toggle()
                    turns += 1
                }
                list.contentOffset.y = y
            }
            last = link.timestamp
            return turns >= passes * 2
        }
        result.frames = intervals.count
        let sorted = intervals.sorted()
        result.median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        return result
    }

    private func run(_ tick: @escaping (CADisplayLink) -> Bool) async {
        self.tick = tick
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        await withCheckedContinuation { done = $0; link.add(to: .main, forMode: .common) }
        link.invalidate()
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard let tick, tick(link) else { return }
        self.tick = nil
        done?.resume()
        done = nil
    }
}
#endif
