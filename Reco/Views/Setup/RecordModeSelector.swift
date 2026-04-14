import SwiftUI

struct RecordModeSelector: View {
    @Binding var selectedMode: RecordMode

    var body: some View {
        HStack(spacing: 12) {
            modeCard(
                mode: .portraitAndScreen,
                title: "Portrait + Screen",
                icon: "person.and.background.dotted",
                description: "Camera overlay on screen"
            )
            modeCard(
                mode: .screenOnly,
                title: "Screen Only",
                icon: "rectangle.inset.filled",
                description: "Screen capture only"
            )
        }
    }

    private func modeCard(mode: RecordMode, title: String, icon: String, description: String) -> some View {
        let isSelected = selectedMode == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMode = mode
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
