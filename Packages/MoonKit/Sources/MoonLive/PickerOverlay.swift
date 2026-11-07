import MoonKit
import MoonUI
import SwiftUI

/// Over the canvas while picking: takes the pointer and every click away from
/// the app, and outlines what a click would pick.
struct PickerOverlay: View {
    @Environment(Workspace.self) private var workspace
    @Environment(Inspection.self) private var inspection

    var body: some View {
        ZStack(alignment: .topLeading) {
            PickSurface { point in
                inspection.aim(at: point)
            } click: { point in
                inspection.aim(at: point)
                inspection.pick(in: workspace)
            }
            .background(Color.accentColor.opacity(0.04))

            if let aim = inspection.aim {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.14))
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: aim.frame.width, height: aim.frame.height)
                    .offset(x: aim.frame.minX, y: aim.frame.minY)
                    .allowsHitTesting(false)

                Text("\(aim.label)  ·  \(aim.scope.mod)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: .capsule)
                    .offset(x: max(aim.frame.minX, 4), y: max(aim.frame.minY - 28, 4))
                    .allowsHitTesting(false)
            }

            // Keys, without taking focus from anything.
            Group {
                Button("Stop picking") { inspection.cancelPicking() }
                    .keyboardShortcut(.cancelAction)
                Button("Out") { inspection.aimOutward() }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("In") { inspection.aimInward() }
                    .keyboardShortcut(.downArrow, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .animation(.snappy(duration: 0.12), value: inspection.aim)
    }
}

#if os(macOS)
/// Takes the pointer and every click from what's under it. AppKit rather than
/// a gesture, so the first click picks even in an inactive window.
private struct PickSurface: NSViewRepresentable {
    let move: (CGPoint?) -> Void
    let click: (CGPoint) -> Void

    func makeNSView(context: Context) -> Surface {
        Surface()
    }

    func updateNSView(_ view: Surface, context: Context) {
        view.move = move
        view.click = click
    }

    final class Surface: NSView {
        var move: (CGPoint?) -> Void = { _ in }
        var click: (CGPoint) -> Void = { _ in }

        // Top left origin, like the canvas it covers.
        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
                owner: self
            ))
        }

        override func mouseMoved(with event: NSEvent) {
            move(point(of: event))
        }

        override func mouseExited(with event: NSEvent) {
            move(nil)
        }

        override func mouseDown(with event: NSEvent) {
            click(point(of: event))
        }

        private func point(of event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }
    }
}
#else
/// Touch has no hover: dragging aims, and lifting picks.
private struct PickSurface: View {
    let move: (CGPoint?) -> Void
    let click: (CGPoint) -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(MoonCanvas.space))
                    .onChanged { move($0.location) }
                    .onEnded { click($0.location) }
            )
            .accessibilityIdentifier("moon.picker")
    }
}
#endif
