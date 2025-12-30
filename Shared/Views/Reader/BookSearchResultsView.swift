import SwiftUI

struct BookSearchResultsView: View {
    let matches: [SearchMatch]
    let onSelectMatch: (SearchMatch) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(matches) { match in
                    Button {
                        onSelectMatch(match)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(match.chapterTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(match.text)
                                .font(.body)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading)
                }
            }
        }
        .background(.bar)
    }
}
