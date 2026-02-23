import SwiftUI
import LockOutCore

struct iOSOnboardingView: View {
    @State private var page = 0
    @State private var breatheScale: CGFloat = 0.5
    @State private var eyeEnabled = true
    @State private var microEnabled = true
    @State private var longEnabled = true
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        TabView(selection: $page) {
            page1.tag(0)
            page2.tag(1)
            page3.tag(2)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private var page1: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "eye.fill").font(.system(size: 80))
            Text("20-20-20 Rule").font(.largeTitle).bold()
            Text("Every 20 minutes, look at something 20 feet away for 20 seconds.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            Spacer()
            Button("Next") { page = 1 }.buttonStyle(.borderedProminent)
        }.padding(40)
    }

    private var page2: some View {
        VStack(spacing: 20) {
            Spacer()
            Circle().fill(Color.blue.opacity(0.3)).frame(width: 80, height: 80).scaleEffect(breatheScale)
                .onAppear { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breatheScale = 1 } }
            Text("Rest Breaks").font(.largeTitle).bold()
            Text("Regular micro and long breaks reduce fatigue and improve focus.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            Spacer()
            Button("Next") { page = 2 }.buttonStyle(.borderedProminent)
        }.padding(40)
    }

    private var page3: some View {
        VStack(spacing: 16) {
            Spacer()
            Button("Enable Notifications") {
                Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
            }.buttonStyle(.borderedProminent)
            Toggle("Enable Eye Breaks", isOn: $eyeEnabled)
            Toggle("Enable Micro Breaks", isOn: $microEnabled)
            Toggle("Enable Long Breaks", isOn: $longEnabled)
            Spacer()
            Button("Get Started") {
                var s = AppSettings.defaults
                s.eyeConfig.isEnabled = eyeEnabled
                s.microConfig.isEnabled = microEnabled
                s.longConfig.isEnabled = longEnabled
                iOSAppDelegate.shared.settings = s
                NotificationScheduler.schedule(settings: s)
                hasOnboarded = true
            }.buttonStyle(.borderedProminent)
        }.padding(40)
    }
}
