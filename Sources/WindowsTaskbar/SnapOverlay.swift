import AppKit
import SwiftUI

final class SnapOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SnapPreviewView: View {
    let zone: SnapZone

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TaskbarTheme.activeIndicator.opacity(0.24))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TaskbarTheme.activeIndicator.opacity(0.95), lineWidth: 2)
        }
        .padding(3)
        .accessibilityLabel(zone.accessibilityLabel)
    }
}

struct SnapLayoutView: View {
    let layouts: [[SnapZone]]
    let onHover: (SnapZone?) -> Void
    let onSelect: (SnapZone) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Snap layouts")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("⌃⌥ + Arrow")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(Array(layouts.enumerated()), id: \.offset) { _, layout in
                    layoutCard(layout)
                }
            }
        }
        .padding(12)
        .background {
            VisualEffectView()
            Color(red: 0.06, green: 0.08, blue: 0.13).opacity(0.82)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        }
        .preferredColorScheme(.dark)
    }

    private func layoutCard(_ zones: [SnapZone]) -> some View {
        HStack(spacing: 3) {
            ForEach(zones) { zone in
                Button {
                    onSelect(zone)
                } label: {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        }
                        .frame(minWidth: 18, minHeight: zones.count == 4 ? 22 : 46)
                }
                .buttonStyle(.plain)
                .help(zone.accessibilityLabel)
                .accessibilityLabel(zone.accessibilityLabel)
                .onHover { hovering in onHover(hovering ? zone : nil) }
            }
        }
        .padding(5)
        .frame(height: 58)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
