import Foundation

enum Formatters {
    /// Fixed-width gigabyte string, e.g. "13.5 GB". One decimal always,
    /// so the menu bar label width stays stable between ticks.
    static func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    /// Adaptive byte string for panel rows: MB, GB, or TB.
    static func bytes(_ bytes: UInt64) -> String {
        let tib = Double(bytes) / 1_099_511_627_776
        if tib >= 1 { return String(format: "%.2f TB", tib) }
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 { return String(format: "%.2f GB", gib) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    static func bytesPerSecond(_ value: Double) -> String {
        let bytes = max(value, 0)
        if bytes >= 1_073_741_824 {
            return String(format: "%.2f GB/s", bytes / 1_073_741_824)
        }
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB/s", bytes / 1_048_576)
        }
        if bytes >= 1_024 {
            return String(format: "%.0f KB/s", bytes / 1_024)
        }
        return String(format: "%.0f B/s", bytes)
    }

    static func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func load(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
