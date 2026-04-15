import SwiftUI

struct RecordModeSelector: View {
    @Binding var selectedMode: RecordMode

    var body: some View {
        HStack(spacing: 14) {
            modeCard(
                mode: .portraitAndScreen,
                title: "Portrait + Screen",
                icon: "person.crop.square.badge.video",
                description: "Layer your camera over the recording with a live stage preview."
            )
            modeCard(
                mode: .screenOnly,
                title: "Screen Only",
                icon: "rectangle.on.rectangle",
                description: "Keep the composition clean and focus entirely on the captured display."
            )
        }
        .animation(.snappy(duration: 0.18), value: selectedMode)
    }

    private func modeCard(mode: RecordMode, title: String, icon: String, description: String) -> some View {
        let isSelected = selectedMode == mode

        return Button {
            selectedMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Color.recoAccent.opacity(0.16) : Color.black.opacity(0.04))
                            .frame(width: 52, height: 52)

                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.recoAccent : .secondary)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.recoAccent : Color.secondary.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.88))

                    Text(description)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(isSelected ? Color.recoAccent.opacity(0.10) : Color.black.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        isSelected ? Color.recoAccent.opacity(0.9) : Color.black.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
