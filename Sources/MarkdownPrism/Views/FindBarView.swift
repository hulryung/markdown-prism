import SwiftUI

struct FindBarView: View {
    @Binding var searchText: String
    @Binding var replaceText: String
    @Binding var isRegex: Bool
    let isReplaceVisible: Bool
    let matchCount: Int
    let currentMatch: Int
    let focusTrigger: Int
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onDismiss: () -> Void
    let onToggleReplace: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            findRow
            if isReplaceVisible {
                replaceRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)
        .onExitCommand { onDismiss() }
        .onAppear { isSearchFieldFocused = true }
        .onChange(of: focusTrigger) {
            isSearchFieldFocused = true
        }
    }

    private var findRow: some View {
        HStack(spacing: 8) {
            Button(action: onToggleReplace) {
                Image(systemName: isReplaceVisible ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.borderless)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Find…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFieldFocused)
                    .onSubmit { onNext() }

                if !searchText.isEmpty {
                    Text(matchCount == 0 ? "No results" : "\(currentMatch) of \(matchCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            Button(action: { isRegex.toggle() }) {
                Text(".*")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRegex ? .white : .secondary)
                    .frame(width: 24, height: 20)
                    .background(isRegex ? Color.accentColor : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            .help("Regular Expression")

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 12)

            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))

                TextField("Replace…", text: $replaceText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            Button("Replace", action: onReplace)
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)

            Button("All", action: onReplaceAll)
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)

            Spacer().frame(width: 20)
        }
    }
}
