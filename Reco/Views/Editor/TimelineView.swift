import SwiftUI
import CoreGraphics

/// Horizontal timeline bar with thumbnail strip, playhead, trim handles,
/// split indicators, and segment selection.
struct TimelineView: View {
    @Bindable var editorState: EditorState

    @State private var isDraggingPlayhead: Bool = false
    @State private var isDraggingTrimStart: Bool = false
    @State private var isDraggingTrimEnd: Bool = false

    private let timelineHeight: CGFloat = 60
    private let handleWidth: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            // Transport controls
            transportBar

            // Timeline strip
            GeometryReader { geometry in
                let totalWidth = geometry.size.width - handleWidth * 2

                ZStack(alignment: .leading) {
                    // Thumbnail strip background
                    thumbnailStrip(width: totalWidth)
                        .offset(x: handleWidth)

                    // Deleted segment overlays
                    deletedSegmentOverlays(totalWidth: totalWidth)
                        .offset(x: handleWidth)

                    // Split indicators
                    splitIndicators(totalWidth: totalWidth)
                        .offset(x: handleWidth)

                    // Segment selection highlight
                    segmentHighlight(totalWidth: totalWidth)
                        .offset(x: handleWidth)

                    // Trim handles
                    trimStartHandle(totalWidth: totalWidth)
                    trimEndHandle(totalWidth: totalWidth, containerWidth: geometry.size.width)

                    // Playhead
                    playhead(totalWidth: totalWidth)
                        .offset(x: handleWidth)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingTrimStart && !isDraggingTrimEnd {
                                let fraction = (value.location.x - handleWidth) / totalWidth
                                let time = Double(fraction) * editorState.duration
                                editorState.seekTo(time)
                                isDraggingPlayhead = true
                            }
                        }
                        .onEnded { _ in
                            isDraggingPlayhead = false
                        }
                )
                .onTapGesture { location in
                    // Select segment on tap
                    let fraction = (location.x - handleWidth) / totalWidth
                    let time = Double(fraction) * editorState.duration
                    selectSegmentAt(time: time)
                }
            }
            .frame(height: timelineHeight)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .task {
            await editorState.generateThumbnails()
        }
    }

    // MARK: - Transport Bar

    private var transportBar: some View {
        HStack(spacing: 16) {
            // Track label
            Menu {
                Button("All Tracks") {}
                Button("Screen Only") {}
            } label: {
                HStack(spacing: 4) {
                    Text("Tracks")
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .fixedSize()

            Spacer()

            // Playback controls
            HStack(spacing: 8) {
                Button {
                    editorState.jumpToStart()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    editorState.togglePlayback()
                } label: {
                    Image(systemName: editorState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    editorState.jumpToEnd()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            // Time display
            Text("\(formatTime(editorState.currentTime)) / \(formatTime(editorState.duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            // Split button
            Button {
                editorState.splitAtPlayhead()
            } label: {
                Image(systemName: "scissors")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Split at playhead (S)")

            // Delete segment button
            Button {
                editorState.deleteSelectedSegment()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(editorState.selectedSegmentIndex == nil)
            .help("Delete selected segment")

            // Zoom controls
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $editorState.zoomLevel, in: 1...10, step: 0.5)
                    .frame(width: 80)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Thumbnail Strip

    @ViewBuilder
    private func thumbnailStrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if editorState.thumbnails.isEmpty {
                // Placeholder strip
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: width, height: timelineHeight)
            } else {
                let thumbWidth = width / CGFloat(editorState.thumbnails.count)
                ForEach(Array(editorState.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbWidth, height: timelineHeight)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: timelineHeight)
    }

    // MARK: - Deleted Segment Overlays

    @ViewBuilder
    private func deletedSegmentOverlays(totalWidth: CGFloat) -> some View {
        let boundaries = editorState.segmentBoundaries
        ForEach(0..<max(boundaries.count - 1, 0), id: \.self) { index in
            if editorState.isSegmentDeleted(index: index) {
                let start = boundaries[index]
                let end = boundaries[index + 1]
                let xStart = CGFloat(start / editorState.duration) * totalWidth
                let segWidth = CGFloat((end - start) / editorState.duration) * totalWidth

                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: segWidth, height: timelineHeight)
                    .offset(x: xStart)
            }
        }
    }

    // MARK: - Split Indicators

    @ViewBuilder
    private func splitIndicators(totalWidth: CGFloat) -> some View {
        ForEach(editorState.splitPoints, id: \.self) { point in
            let x = CGFloat(point / editorState.duration) * totalWidth
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 2, height: timelineHeight)
                .offset(x: x - 1)
        }
    }

    // MARK: - Segment Highlight

    @ViewBuilder
    private func segmentHighlight(totalWidth: CGFloat) -> some View {
        if let selectedIndex = editorState.selectedSegmentIndex {
            let boundaries = editorState.segmentBoundaries
            if selectedIndex < boundaries.count - 1 {
                let start = boundaries[selectedIndex]
                let end = boundaries[selectedIndex + 1]
                let xStart = CGFloat(start / editorState.duration) * totalWidth
                let segWidth = CGFloat((end - start) / editorState.duration) * totalWidth

                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: segWidth, height: timelineHeight)
                    .offset(x: xStart)
            }
        }
    }

    // MARK: - Trim Handles

    @ViewBuilder
    private func trimStartHandle(totalWidth: CGFloat) -> some View {
        let x = CGFloat(editorState.trimStart / editorState.duration) * totalWidth

        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: handleWidth, height: timelineHeight)
            .offset(x: x)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDraggingTrimStart = true
                        let fraction = value.location.x / totalWidth
                        let time = max(0, Double(fraction) * editorState.duration)
                        editorState.trimStart = min(time, editorState.trimEnd - 1)
                    }
                    .onEnded { _ in
                        isDraggingTrimStart = false
                    }
            )
            .cursor(.resizeLeftRight)
    }

    @ViewBuilder
    private func trimEndHandle(totalWidth: CGFloat, containerWidth: CGFloat) -> some View {
        let x = CGFloat(editorState.trimEnd / editorState.duration) * totalWidth + handleWidth

        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: handleWidth, height: timelineHeight)
            .offset(x: x)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDraggingTrimEnd = true
                        let fraction = (value.location.x - handleWidth) / totalWidth
                        let time = min(editorState.duration, Double(fraction) * editorState.duration)
                        editorState.trimEnd = max(time, editorState.trimStart + 1)
                    }
                    .onEnded { _ in
                        isDraggingTrimEnd = false
                    }
            )
            .cursor(.resizeLeftRight)
    }

    // MARK: - Playhead

    @ViewBuilder
    private func playhead(totalWidth: CGFloat) -> some View {
        let x = CGFloat(editorState.currentTime / editorState.duration) * totalWidth

        ZStack(alignment: .top) {
            // Playhead line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: timelineHeight + 8)

            // Playhead handle (top triangle)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .offset(y: -8)
        }
        .offset(x: x - 1)
    }

    // MARK: - Helpers

    private func selectSegmentAt(time: TimeInterval) {
        let boundaries = editorState.segmentBoundaries
        for i in 0..<(boundaries.count - 1) {
            if time >= boundaries[i] && time < boundaries[i + 1] {
                editorState.selectedSegmentIndex = i
                return
            }
        }
        editorState.selectedSegmentIndex = nil
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Cursor Extension

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
