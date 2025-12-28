# Crux - Claude Code Instructions

## Project Overview
Crux is an AI-native EPUB reader for macOS/iOS with Claude-powered passage explication.

## Tech Stack
- SwiftUI (shared codebase for macOS 14+ / iOS 17+)
- WKWebView for EPUB content rendering
- SwiftData for library persistence
- Claude API for AI features

## Key Directories
- `Shared/Models/` - Data models (Book, Chapter, Annotations, etc.)
- `Shared/Views/` - SwiftUI views
- `Shared/Services/` - EPUBParser, ClaudeService, BookStorage

## Build Commands
```bash
# Generate Xcode project
xcodegen generate

# Build macOS
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build

# Run tests
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' test
```

## Important: Progress Logging
**Always log changes to the project file at:**
`~/projects/crux-epub-reader.md`

After completing any feature or bug fix, append a dated entry to the Progress Log section describing what was done.
