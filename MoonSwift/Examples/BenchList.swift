import SwiftUI

/// Benchmark B1's baseline: the screen of `examples/bench`, written by hand
/// in SwiftUI, as Sheprd writes its lists.
struct BenchList: View {
    private static let symbols = ["asterisk", "circle.hexagonpath", "sparkle", "terminal"]
    private static let colors: [Color] = [.orange, .gray, .blue, .green]

    var body: some View {
        NavigationStack {
            List(1...10_000, id: \.self) { index in
                let kind = index % 4
                HStack(spacing: 12) {
                    Image(systemName: Self.symbols[kind])
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Self.colors[kind], in: .rect(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: "Session \(index)").lineLimit(1)
                            Spacer(minLength: 0)
                            Text(verbatim: "\(index % 60)m").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Text(verbatim: "Studio · forecast · Row \(index) of the benchmark")
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .accessibilityIdentifier("bench.list")
            .navigationTitle("SwiftUI")
        }
    }
}
