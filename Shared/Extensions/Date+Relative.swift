import Foundation

extension Date {
    /// Returns a relative date string like "3d ago" or "2h ago"
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Returns a short relative string without "ago" - just "3d", "2h", etc.
    var relativeShort: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else if interval < 604800 {
            return "\(Int(interval / 86400))d"
        } else if interval < 2592000 {
            return "\(Int(interval / 604800))w"
        } else if interval < 31536000 {
            return "\(Int(interval / 2592000))mo"
        } else {
            return "\(Int(interval / 31536000))y"
        }
    }
}
