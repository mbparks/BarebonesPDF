import SwiftUI

struct SearchBar: View {
    @ObservedObject var state: DocumentState
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search this PDF", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { state.performSearch() }
                .accessibilityLabel("Search this PDF")

            if state.isSearching {
                ProgressView().controlSize(.small)
            } else if !state.searchQuery.isEmpty {
                Text(resultSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Button { state.previousSearchResult() } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(state.searchResults.isEmpty)
            .help("Previous search result")
            .accessibilityLabel("Previous search result")

            Button { state.nextSearchResult() } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(state.searchResults.isEmpty)
            .help("Next search result")
            .accessibilityLabel("Next search result")

            Button { state.closeSearch() } label: {
                Image(systemName: "xmark")
            }
            .help("Close search")
            .accessibilityLabel("Close search")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        .onAppear { searchFocused = true }
        .onChange(of: state.searchQuery) { _ in state.performSearch() }
    }

    private var resultSummary: String {
        if state.searchResults.isEmpty { return "No results" }
        return "\(state.searchResultIndex + 1) of \(state.searchResults.count)"
    }
}
