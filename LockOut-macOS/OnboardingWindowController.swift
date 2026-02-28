import AppKit
import SwiftUI
import EventKit
import LockOutCore

final class OnboardingWindowController: NSWindowController {
    private static var instance: OnboardingWindowController?

    static func present(scheduler: BreakScheduler) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome to LockOut"
        win.center()
        win.contentView = NSHostingView(rootView: OnboardingView(scheduler: scheduler) { win.close() })
        let ctrl = OnboardingWindowController(window: win)
        instance = ctrl
        ctrl.showWindow(nil)
    }
}

struct OnboardingView: View {
    let scheduler: BreakScheduler
    let onFinish: () -> Void
    @State private var page = 0
    @State private var breatheScale: CGFloat = 0.5

    @State private var enableCalendar = false
    @State private var enableFocus = false

    var body: some View {
        TabView(selection: $page) {
            page1.tag(0)
            page2.tag(1)
            pageNotifications.tag(2)
            pageIntegrations.tag(3)
            page3.tag(4)
        }
        .tabViewStyle(.automatic)
        .frame(width: 480, height: 520)
    }

    private var page1: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "eye").font(.system(size: 72))
            Text("20-20-20 Rule").font(.title).bold()
            Text("Every 20 minutes, look at something 20 feet away for at least 20 seconds to reduce digital eye strain.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button("Next") { page = 1 }.buttonStyle(.borderedProminent)
        }.padding(40)
    }

    private var page2: some View {
        VStack(spacing: 16) {
            Spacer()
            Circle().fill(Color.blue.opacity(0.3)).frame(width: 80, height: 80).scaleEffect(breatheScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breatheScale = 1 }
                }
            Text("Rest Breaks").font(.title).bold()
            Text("Micro breaks (45 min) and long breaks (90 min) help reduce fatigue and keep you focused throughout the day.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button("Next") { page = 2 }.buttonStyle(.borderedProminent)

        }.padding(40)
    }

    private var pageIntegrations: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 64))
            Text("Optional Integrations").font(.title).bold()
            Text("LockOut can pause during calendar events or Focus Mode.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Toggle("Pause during Calendar events", isOn: $enableCalendar)
            Toggle("Pause during Focus Mode", isOn: $enableFocus)
            Spacer()
            Button("Continue") {
                scheduler.currentSettings.pauseDuringCalendarEvents = enableCalendar
                scheduler.currentSettings.pauseDuringFocus = enableFocus
                if enableCalendar {
                    EKEventStore().requestFullAccessToEvents { _, _ in }
                }
                page = 4
            }.buttonStyle(.borderedProminent)
        }.padding(40)
    }

    private var pageNotifications: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.badge").font(.system(size: 64))
            Text("Break Reminders").font(.title).bold()
            Text("LockOut sends a reminder before each break so you can wrap up your current task.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 12) {
                Button("Skip") { page = 3 }
                    .buttonStyle(.bordered)
                Button("Allow Notifications") {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    DispatchQueue.main.async { page = 3 }
                }
                .buttonStyle(.borderedProminent)
            }
        }.padding(40)
    }

    private var page3: some View {
        VStack(spacing: 16) {
            Spacer()
            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLoginService.isEnabled },
                set: { $0 ? LaunchAtLoginService.enable() : LaunchAtLoginService.disable() }
            ))
            Spacer()
            Button("Get Started") {
                UserDefaults.standard.set(true, forKey: "hasOnboarded")
                onFinish()
            }.buttonStyle(.borderedProminent)
        }.padding(40)
    }
}
