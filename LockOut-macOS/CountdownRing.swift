import SwiftUI

struct CountdownRing: View {
    let progress: Double     // 0.0 - 1.0
    let label: String
    let timeString: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .foregroundStyle(.blue)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            VStack(spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(timeString).font(.title2.monospacedDigit()).bold()
            }
        }
        .frame(width: 120, height: 120)
    }
}
