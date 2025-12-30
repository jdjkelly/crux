import SwiftUI

struct InlineSearchBar: View {
    @Bindable var searchState: SearchState
    let onSearch: (String) -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    let onScopeChange: (SearchScope) -> Void

    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Search input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search...", text: $searchState.query)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit { onNext() }
                    .onChange(of: searchState.query) { _, newValue in
                        onSearch(newValue)
                    }

                if !searchState.query.isEmpty {
                    Button {
                        searchState.query = ""
                        onSearch("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary)
            .cornerRadius(8)
            .frame(maxWidth: 280)

            // Match counter
            if !searchState.query.isEmpty {
                Text(matchCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 60)
            }

            // Navigation buttons
            HStack(spacing: 4) {
                Button { onPrevious() } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!searchState.hasMatches)
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button { onNext() } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!searchState.hasMatches)
                .keyboardShortcut(.downArrow, modifiers: .command)
            }
            .buttonStyle(.bordered)

            // Scope picker (in-chapter vs book-wide)
            Picker("Scope", selection: $searchState.scope) {
                Text("Chapter").tag(SearchScope.chapter)
                Text("Book").tag(SearchScope.book)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .onChange(of: searchState.scope) { _, newScope in
                onScopeChange(newScope)
            }

            Spacer()

            // Close button
            Button { onClose() } label: {
                Text("Done")
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear {
            isInputFocused = true
        }
    }

    private var matchCountText: String {
        switch searchState.scope {
        case .chapter:
            if searchState.inChapterMatchCount == 0 {
                return "No matches"
            }
            return "\(searchState.inChapterCurrentIndex + 1) of \(searchState.inChapterMatchCount)"
        case .book:
            let count = searchState.bookMatches.count
            if count == 0 { return "No matches" }
            return count == 1 ? "1 match" : "\(count) matches"
        }
    }
}
