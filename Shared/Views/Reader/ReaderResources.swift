import Foundation

/// Loads reader resources from the app bundle for WKWebView
enum ReaderResources {

    /// Platform identifier for template substitution
    enum Platform: String {
        case macOS = "macos"
        case iOS = "ios"

        static var current: Platform {
            #if os(macOS)
            return .macOS
            #else
            return .iOS
            #endif
        }
    }

    /// Base URL for reader resources in bundle (for relative script/css loading)
    static var baseURL: URL? {
        Bundle.main.url(forResource: "reader-template", withExtension: "html")?
            .deletingLastPathComponent()
    }

    /// Loads a JavaScript file from the Reader bundle directory
    static func loadScript(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return content
    }

    /// Loads the CSS file from the Reader bundle directory
    static func loadCSS() -> String? {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "css"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return content
    }

    /// Loads and populates the HTML template with content
    static func buildHTML(content: String, platform: Platform = .current) -> String? {
        guard let templateURL = Bundle.main.url(forResource: "reader-template", withExtension: "html"),
              var template = try? String(contentsOf: templateURL, encoding: .utf8) else {
            return nil
        }

        template = template
            .replacingOccurrences(of: "{{PLATFORM}}", with: platform.rawValue)
            .replacingOccurrences(of: "{{CONTENT}}", with: content)

        return template
    }
}
