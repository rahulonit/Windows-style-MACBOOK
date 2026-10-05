import SwiftUI

struct ClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 0) {
                Text(context.date, format: .dateTime.hour().minute())
                Text(context.date, format: .dateTime.day().month().year())
            }
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(TaskbarTheme.foreground)
            .monospacedDigit()
            .frame(minWidth: 72, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(context.date.formatted(date: .long, time: .shortened))
        }
    }
}
