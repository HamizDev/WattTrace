import SwiftUI
import UIKit

struct RootView: View {
    @Environment(PowerMonitor.self) private var monitor
    @Environment(FloatingMeterController.self) private var floatingMeter
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveActivity = ChargeActivityController()
    @State private var widgets = WidgetPublisher()
    @State private var selectedTab: AppTab = .power

    var body: some View {
        tabs
        .tint(.mwAccent)
        .background { ScreenAwakeHolder() }
        // The layer Picture in Picture draws from has to be on screen for the system
        // to open a window from it, so it sits here, a few points across, for the
        // life of the app. Nothing is ever read off it here.
        .background(alignment: .topLeading) {
            FloatingMeterStage(controller: floatingMeter)
                .frame(width: 16, height: 9)
                .opacity(0.02)
                .allowsHitTesting(false)
        }
        .task {
            // Every glance is fed from the tick rather than from `onChange`: SwiftUI
            // stops updating views once the app is off screen, and off screen is
            // exactly where the floating meter earns its keep. Each consumer
            // throttles itself; this only hands over the reading.
            monitor.onTick = { [liveActivity, widgets, floatingMeter] snapshot in
                let reading = ChargeReading(snapshot)
                floatingMeter.render(snapshot: snapshot,
                                     thermalState: monitor.thermal.state,
                                     temperatureUnit: monitor.temperatureUnit)
                liveActivity.sync(snapshot,
                                  selectedMetric: monitor.liveActivityMetric,
                                  temperatureUnit: monitor.temperatureUnit,
                                  enabled: monitor.showsLiveActivityWhileCharging,
                                  isForeground: UIApplication.shared.applicationState == .active)
                widgets.publish(reading, lastSession: monitor.sessions.first)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                monitor.start()
            case .background:
                // Sensor reads are pointless while suspended, so the tick stops —
                // but an open charge session stays open. It ends when the charger
                // comes out, not when the app goes off screen.
                //
                // Unless the floating meter is up: PiP keeps the process running, so
                // the sensors can still be read, the window keeps a live number on
                // screen and the charge is recorded through a locked screen.
                if !floatingMeter.isRunning {
                    monitor.pause()
                }
                // Last chance to leave the widget something fresh to fall back on.
                widgets.flush(ChargeReading(monitor.snapshot), lastSession: monitor.sessions.first)
            default:
                // `.inactive` is transient and the app is still on screen for most
                // of it: a pulled-down Control Center, the app switcher, an
                // incoming call. Nothing to do.
                break
            }
        }
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: $selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    Tab(value: tab) { tab.page } label: { tab.label }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    tab.page
                        .tabItem { tab.label }
                        .tag(tab)
                }
            }
        }
    }
}

private enum AppTab: CaseIterable, Identifiable {
    case power, thermal, adapter, devices, history

    var id: Self { self }

    private var appearance: (title: LocalizedStringResource, symbol: String) {
        switch self {
        case .power: ("Power", "bolt.fill")
        case .thermal: ("Thermal", "thermometer.medium")
        case .adapter: ("Adapter", "powerplug.fill")
        case .devices: ("Devices", "square.stack.3d.up.fill")
        case .history: ("History", "chart.xyaxis.line")
        }
    }

    var label: some View {
        Label { Text(appearance.title) } icon: { Image(systemName: appearance.symbol) }
    }

    var page: some View {
        TabPage {
            switch self {
            case .power: DashboardView()
            case .thermal: ThermalView()
            case .adapter: AdapterView()
            case .devices: DevicesView()
            case .history: SessionsView()
            }
        }
    }
}

/// A tab's page, built only while the tab is on screen.
///
/// A `TabView` keeps every tab that has been visited alive, and keeps updating it:
/// each page reads the monitor, so each one was re-evaluated on every tick, on
/// screen or not. With all five visited that was five pages rebuilt once a second,
/// and scrolling the one in front hitched at exactly that rhythm. The price is that
/// a tab comes back scrolled to the top.
///
/// The switch has to live inside the tab. Deciding it in `RootView` from the
/// selection does not work: a tab that is not showing never receives its parent's
/// update, so it kept the page it had and went on updating it.
private struct TabPage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var isOnScreen = true

    var body: some View {
        ZStack {
            if isOnScreen {
                content()
            } else {
                Color.clear
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }
}

/// Holds the screen on, but only while it is actually earning something: the app
/// is in front and the phone is plugged in. Keeping a battery instrument awake on
/// battery would be a poor joke.
///
/// A view of its own because deciding needs the snapshot, which changes every
/// second. Read in `RootView`'s body, it re-ran that body — and the tab view under
/// it — on every tick; here it re-runs an empty view.
private struct ScreenAwakeHolder: View {
    @Environment(PowerMonitor.self) private var monitor
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .onChange(of: shouldStayAwake, initial: true) { _, awake in
                UIApplication.shared.isIdleTimerDisabled = awake
            }
    }

    private var shouldStayAwake: Bool {
        monitor.keepScreenAwakeWhileCharging
            && monitor.snapshot.externalConnected
            && scenePhase == .active
    }
}

/// System navigation around panels. PageContent contains the live dependencies
/// so the title and toolbar do not need to be evaluated on each sensor tick.
struct PageScaffold<Content: View>: View {
    let title: LocalizedStringResource
    var toolbar: AnyView?
    var layout: PanelLayout
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringResource,
         toolbar: AnyView? = nil,
         layout: PanelLayout = .panels,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.toolbar = toolbar
        self.layout = layout
        self.content = content
    }

    var body: some View {
        NavigationStack {
            PanelScroll(layout: layout, content: content)
                .background { Backdrop() }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if let toolbar {
                        ToolbarItem(placement: .topBarTrailing) { toolbar }
                    }
                }
        }
    }
}

/// Used wherever a probe legitimately has nothing to report.
/// Shown where the input figure would be, when the input sensors answered but more
/// power is reaching the cell than they account for. See `PowerSnapshot.partialInputWatts`.
struct PartialInputNote: View {
    let sensedWatts: Double
    let cellWatts: Double

    var body: some View {
        EmptyNote(text: "The input sensors read \(Formatting.watts(sensedWatts)) W while \(Formatting.watts(cellWatts)) W is reaching the cell, so on this model they see only part of what comes in. That figure is not shown as the input, and nothing is worked out from it.",
                  systemImage: "exclamationmark.triangle")
    }
}

struct EmptyNote: View {
    let text: LocalizedStringResource
    var systemImage: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.medium))
                .accessibilityHidden(true)
                .foregroundStyle(Color.mwMuted)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.mwMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
