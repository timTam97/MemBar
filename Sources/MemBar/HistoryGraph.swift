import SwiftUI

/// Activity Monitor-style scrolling history graphs. Samples are right-aligned:
/// the newest sample sits at the right edge and history extends leftward, so a
/// freshly launched app shows data growing in from the right.
private enum Graph {
    static let height: CGFloat = 64

    static func x(index: Int, count: Int, width: CGFloat) -> CGFloat {
        let step = width / CGFloat(StatsModel.historyCapacity - 1)
        return width - CGFloat(count - 1 - index) * step
    }

    static func y(_ percent: Double, height: CGFloat) -> CGFloat {
        height * (1 - min(max(percent, 0), 100) / 100)
    }
}

/// Plot surface shared by both graphs: recessive solid hairline grid at
/// 25/50/75% and a border, one shade off the menu background.
private struct GraphSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(height: Graph.height)
            .frame(maxWidth: .infinity)
            .background {
                Canvas { context, size in
                    var grid = Path()
                    for fraction in [0.25, 0.5, 0.75] {
                        let y = size.height * fraction
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(.primary.opacity(0.07)), lineWidth: 1)
                }
                .background(.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Stacked CPU history: system time filled from the baseline, user time
/// stacked above it, each with a stroked top edge — same composition as
/// Activity Monitor's CPU Load pane.
struct CPUHistoryGraph: View {
    var history: [CPUUsage]

    var body: some View {
        Canvas { context, size in
            guard history.count > 1 else { return }

            let system = history.map(\.system)
            let total = history.map { $0.system + $0.user }
            drawBand(&context, size: size, top: total, bottom: system, color: .blue)
            drawBand(
                &context, size: size, top: system,
                bottom: [Double](repeating: 0, count: history.count), color: .red)
        }
        .modifier(GraphSurface())
        .accessibilityLabel("CPU load history")
        .accessibilityValue(
            history.last.map { "user \(Formatters.pct($0.user)), system \(Formatters.pct($0.system))" }
                ?? "sampling")
    }

    /// Fills the region between two percent series and strokes the top edge.
    private func drawBand(
        _ context: inout GraphicsContext, size: CGSize,
        top: [Double], bottom: [Double], color: Color
    ) {
        let count = top.count
        var edge = Path()
        for i in 0..<count {
            let point = CGPoint(
                x: Graph.x(index: i, count: count, width: size.width),
                y: Graph.y(top[i], height: size.height))
            if i == 0 { edge.move(to: point) } else { edge.addLine(to: point) }
        }

        var fill = edge
        for i in stride(from: count - 1, through: 0, by: -1) {
            fill.addLine(
                to: CGPoint(
                    x: Graph.x(index: i, count: count, width: size.width),
                    y: Graph.y(bottom[i], height: size.height)))
        }
        fill.closeSubpath()

        context.fill(fill, with: .color(color.opacity(0.25)))
        context.stroke(edge, with: .color(color), lineWidth: 1.5)
    }
}

/// Memory pressure history. Each time slice is tinted by the pressure level
/// the kernel reported at that moment (green / yellow / red), matching both
/// Activity Monitor and this menu's pressure dot.
struct PressureHistoryGraph: View {
    var history: [PressureSample]

    var body: some View {
        Canvas { context, size in
            guard history.count > 1 else { return }

            // Consecutive same-level samples form one run, drawn as a single
            // fill + stroked top edge so color changes exactly where the
            // kernel's level changed.
            var runStart = 0
            for i in 1...history.count {
                let runEnded = i == history.count || history[i].level != history[runStart].level
                guard runEnded else { continue }
                // Extend to the next sample so adjacent runs meet seamlessly.
                let end = min(i, history.count - 1)
                drawRun(&context, size: size, range: runStart...end)
                runStart = i
            }
        }
        .modifier(GraphSurface())
        .accessibilityLabel("Memory pressure history")
        .accessibilityValue(
            history.last.map { "\(Int($0.percent)) percent" } ?? "sampling")
    }

    private func drawRun(
        _ context: inout GraphicsContext, size: CGSize, range: ClosedRange<Int>
    ) {
        let color = Self.color(for: history[range.lowerBound].level)
        let count = history.count

        var edge = Path()
        for i in range {
            let point = CGPoint(
                x: Graph.x(index: i, count: count, width: size.width),
                y: Graph.y(history[i].percent, height: size.height))
            if i == range.lowerBound { edge.move(to: point) } else { edge.addLine(to: point) }
        }

        var fill = edge
        fill.addLine(
            to: CGPoint(
                x: Graph.x(index: range.upperBound, count: count, width: size.width),
                y: size.height))
        fill.addLine(
            to: CGPoint(
                x: Graph.x(index: range.lowerBound, count: count, width: size.width),
                y: size.height))
        fill.closeSubpath()

        context.fill(fill, with: .color(color.opacity(0.25)))
        context.stroke(edge, with: .color(color), lineWidth: 1.5)
    }

    static func color(for level: Int32) -> Color {
        switch level {
        case 4: .red
        case 2: .yellow
        default: .green
        }
    }
}

/// Disk throughput history. Read and write rates share a dynamic scale so
/// their relative sizes remain visible across both idle and busy periods.
struct DiskHistoryGraph: View {
    var history: [DiskActivity]

    var body: some View {
        Canvas { context, size in
            guard history.count > 1 else { return }

            let maximum = max(
                history.map {
                    max($0.readBytesPerSecond, $0.writeBytesPerSecond)
                }.max() ?? 0,
                1)
            drawSeries(
                &context,
                size: size,
                values: history.map(\.writeBytesPerSecond),
                maximum: maximum,
                color: .red)
            drawSeries(
                &context,
                size: size,
                values: history.map(\.readBytesPerSecond),
                maximum: maximum,
                color: .blue)
        }
        .modifier(GraphSurface())
        .accessibilityLabel("Disk activity history")
        .accessibilityValue(
            history.last.map {
                "read \(Formatters.bytesPerSecond($0.readBytesPerSecond)), write \(Formatters.bytesPerSecond($0.writeBytesPerSecond))"
            } ?? "sampling")
    }

    private func drawSeries(
        _ context: inout GraphicsContext, size: CGSize,
        values: [Double], maximum: Double, color: Color
    ) {
        var edge = Path()
        for i in values.indices {
            let point = CGPoint(
                x: Graph.x(index: i, count: values.count, width: size.width),
                y: size.height * (1 - min(max(values[i] / maximum, 0), 1)))
            if i == values.startIndex { edge.move(to: point) } else { edge.addLine(to: point) }
        }

        var fill = edge
        fill.addLine(
            to: CGPoint(
                x: Graph.x(index: values.count - 1, count: values.count, width: size.width),
                y: size.height))
        fill.addLine(
            to: CGPoint(
                x: Graph.x(index: 0, count: values.count, width: size.width),
                y: size.height))
        fill.closeSubpath()

        context.fill(fill, with: .color(color.opacity(0.18)))
        context.stroke(edge, with: .color(color), lineWidth: 1.5)
    }
}
