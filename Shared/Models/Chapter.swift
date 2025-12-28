import Foundation

struct Chapter: Identifiable, Hashable {
    let id: String
    let title: String
    let href: String
    let content: String
    let order: Int
    let depth: Int  // Hierarchy depth (0 = top level, 1 = nested, etc.)

    init(
        id: String,
        title: String,
        href: String,
        content: String = "",
        order: Int,
        depth: Int = 0
    ) {
        self.id = id
        self.title = title
        self.href = href
        self.content = content
        self.order = order
        self.depth = depth
    }

    /// The file path portion of href (without fragment)
    var filePath: String {
        if let hashIndex = href.firstIndex(of: "#") {
            return String(href[..<hashIndex])
        }
        return href
    }

    /// The fragment/anchor portion of href (after #)
    var fragment: String? {
        if let hashIndex = href.firstIndex(of: "#") {
            let fragmentStart = href.index(after: hashIndex)
            return String(href[fragmentStart...])
        }
        return nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Chapter, rhs: Chapter) -> Bool {
        lhs.id == rhs.id
    }
}
