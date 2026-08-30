import SwiftUI

struct StatusBar: View {
    @ObservedObject var state: DocumentState

    var body: some View {
        HStack(spacing: 10) {
            if state.isEdited {
                Label("Edited", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Document has unsaved changes")
            } else {
                Text("Saved")
                    .foregroundStyle(.secondary)
            }

            if state.isBusy {
                Divider().frame(height: 12)
                ProgressView().controlSize(.small)
                Text(state.busyMessage)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(state.selectedPageSummary)
                .foregroundStyle(.secondary)
            Divider().frame(height: 12)
            Text(state.pageDisplayText)
                .monospacedDigit()
            Divider().frame(height: 12)
            Text("\(state.zoomPercent)%")
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 25)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.pageDisplayText), zoom \(state.zoomPercent) percent")
    }
}
