import SwiftUI

struct StartMenuLogoView: View {
    let style: StartMenuLogoStyle
    let size: CGFloat
    var color: Color = TaskbarTheme.foreground

    var body: some View {
        Group {
            switch style {
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(color)
            case .windows:
                WindowsLogoShape()
                    .fill(color)
                    .frame(width: size * 0.88, height: size * 0.88)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct WindowsLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let gap = rect.width * 0.075
        let paneWidth = (rect.width - gap) / 2
        let paneHeight = (rect.height - gap) / 2
        var path = Path()

        path.addRoundedRect(
            in: CGRect(x: 0, y: 0, width: paneWidth, height: paneHeight),
            cornerSize: CGSize(width: 0.8, height: 0.8)
        )
        path.addRoundedRect(
            in: CGRect(x: paneWidth + gap, y: 0, width: paneWidth, height: paneHeight),
            cornerSize: CGSize(width: 0.8, height: 0.8)
        )
        path.addRoundedRect(
            in: CGRect(x: 0, y: paneHeight + gap, width: paneWidth, height: paneHeight),
            cornerSize: CGSize(width: 0.8, height: 0.8)
        )
        path.addRoundedRect(
            in: CGRect(
                x: paneWidth + gap,
                y: paneHeight + gap,
                width: paneWidth,
                height: paneHeight
            ),
            cornerSize: CGSize(width: 0.8, height: 0.8)
        )
        return path
    }
}
