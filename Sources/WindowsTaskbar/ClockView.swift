import SwiftUI

struct ClockView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 0) {
                Text(context.date, format: .dateTime.hour().minute())
                Text(context.date, format: .dateTime.day().month().year())
            }
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(TaskbarTheme.foreground)
            .monospacedDigit()
            .padding(.horizontal, 7)
            .frame(width: width, height: height, alignment: .trailing)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(context.date.formatted(date: .long, time: .shortened))
        }
    }
}
