import SwiftUI

struct WindowsGlyph: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                pane
                pane
            }
            HStack(spacing: 2) {
                pane
                pane
            }
        }
        .frame(width: 20, height: 20)
    }

    private var pane: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.15, green: 0.72, blue: 1), Color(red: 0.02, green: 0.47, blue: 0.91)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}
