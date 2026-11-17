import BogoSection
import SwiftUI
#if DEBUG
import BogoRelay
#endif

@main
struct AppleBridgeApp: App {
    @UIApplicationDelegateAdaptor(BridgeAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            Group {
                if RealQualification.active { RealQualificationScreen() }
                else if ShellDeliveryQualification.active { ShellDeliveryQualificationScreen() }
                else { BridgeSettings() }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            #else
            BridgeSettings()
            #endif
        }
    }
}

struct BridgeSettings: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var pairing = PairingState()
    @State private var selected = ShellTab.bogo
    @Bindable private var bogo = BogoEdge.shared.section
    var body: some View {
        TabView(selection: $selected) {
            ForEach(ShellModel.tabs) { tab in
                Group {
                    switch tab {
                    case .bogo: bogo.home
                    case .activity: bogo.activity
                    case .settings: NavigationStack { SettingsScreen(pairing: pairing, bogo: bogo) }
                    }
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        .tint(Ink.primary)
        .onChange(of: selected) { Haptics.select() }
        .onChange(of: bogo.focusRequests) { selected = .bogo }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !RealQualification.active {
                LocationCapability.resume()
                WidgetsCapability.resume()
                Task { await pairing.check(); await PushDelivery.shared.drain(); await HealthReadController.shared.resume() }
            }
        }
        .task {
            if await RealQualification.runIfRequested() { return }
            LocationCapability.resume()
            WidgetsCapability.resume()
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--pair-code"), ProcessInfo.processInfo.arguments.count > index + 1 {
                await pairing.pair(ProcessInfo.processInfo.arguments[index + 1])
            }
            await pairing.check()
            await PushDelivery.shared.drain()
            await HealthReadController.shared.resume()
        }
    }
}

struct SettingsScreen: View {
    @Bindable var pairing: PairingState
    let bogo: BogoSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Settings").type(.title).foregroundStyle(Ink.primary).padding(.top, Space.xs).accessibilityAddTraits(.isHeader)
                group("BOGO") {
                    NavigationLink { bogo.macs } label: {
                        SettingsRow(symbol: "laptopcomputer", title: "Macs", detail: "Where your agents run")
                    }
                }
                group("Apple Bridge") {
                    NavigationLink { PairingScreen(state: pairing) } label: {
                        SettingsRow(symbol: "link", title: "Gateway pairing", detail: pairing.status)
                    }
                }
                group("Capabilities") {
                    ForEach(Array(Capabilities.all.enumerated()), id: \.element.id) { index, capability in
                        if index > 0 { Hairline().padding(.leading, 56) }
                        NavigationLink {
                            if capability.id == "screentime" {
                                ScreenTimeScreen()
                            } else {
                                CapabilityScreen(capability: capability)
                            }
                        } label: {
                            SettingsRow(symbol: SettingsRow.symbol(capability.id), title: capability.title, detail: "\(capability.permission) · No activity")
                        }
                    }
                }
                group("Support") {
                    NavigationLink { DiagnosticsScreen(pairing: pairing) } label: {
                        SettingsRow(symbol: "waveform.path.ecg", title: "Diagnostics", detail: "Version, gateway and push delivery")
                    }
                }
                #if DEBUG
                DemoControls(bogo: bogo)
                #endif
                Text("Apple Bridge \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · BOGO")
                    .type(.caption)
                    .foregroundStyle(Ink.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xxl)
        }
        .scrollIndicators(.hidden)
        .canvas()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow(title)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, Space.m)
                .card(padding: 0, radius: Radius.inner + 4)
        }
    }
}

struct SettingsRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Space.s) {
            Tile(symbol: symbol, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).type(.callout, weight: .semibold).foregroundStyle(Ink.primary)
                Text(detail).type(.caption).foregroundStyle(Ink.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: Space.xs)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.tertiary)
        }
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "alarms": return "alarm"
        case "notifications": return "bell.badge"
        case "location": return "location"
        case "healthread": return "heart.text.square"
        case "healthwrite": return "heart"
        case "motion": return "figure.walk"
        case "device-context": return "iphone"
        case "screentime": return "hourglass"
        case "siri": return "mic"
        case "widgets": return "square.grid.2x2"
        case "capture": return "camera"
        case "context": return "text.bubble"
        default: return "circle.grid.2x2"
        }
    }
}

struct DiagnosticsScreen: View {
    @Bindable var pairing: PairingState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(spacing: 0) {
                    DetailRow(Text("Version")) { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") }
                    Hairline()
                    DetailRow(Text("Gateway")) { Text(pairing.status) }
                    Hairline()
                    DetailRow(Text("Capabilities")) { Text(String(Capabilities.all.count)).monospacedDigit() }
                    Hairline()
                    DetailRow(Text("Last command")) { Text(PushDelivery.shared.lastResult) }
                    Hairline()
                    DetailRow(Text("Push delivery")) { Text(PushDelivery.shared.status) }
                    Hairline()
                    DetailRow(Text("Push wakes")) { Text(String(PushDelivery.shared.wakeCount)).monospacedDigit() }
                }
                .padding(.horizontal, Space.l)
                .card(padding: 0, radius: Radius.inner + 4)
                Button("Check pending commands") { Task { await PushDelivery.shared.drain() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(Space.gutter)
        }
        .canvas()
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
struct DemoControls: View {
    let bogo: BogoSection
    @State private var quiet = StandInMacLink.quiet
    @State private var sent: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow("Demo · Debug builds only")
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: $quiet) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quiet stand-in Mac").type(.callout, weight: .semibold).foregroundStyle(Ink.primary)
                        Text("Add Mac sends no sample requests").type(.caption).foregroundStyle(Ink.secondary)
                    }
                }
                .tint(Ink.positive)
                .padding(.vertical, Space.s)
                .onChange(of: quiet) { _, value in StandInMacLink.quiet = value }
                ForEach(DemoRequest.allCases, id: \.self) { request in
                    Hairline()
                    Button { send(request) } label: {
                        HStack {
                            Text(request.title).type(.callout, weight: .medium).foregroundStyle(Ink.primary)
                            Spacer()
                            Text(sent == request.rawValue ? "Arrives in 3 s" : "Send").type(.caption, weight: .semibold).foregroundStyle(Ink.accent)
                        }
                        .padding(.vertical, Space.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.m)
            .card(padding: 0, radius: Radius.inner + 4)
            Text(bogo.standIn?.connected == true ? "Requests come from the stand-in Mac, 3 seconds after you tap." : "Add the Stand-in Mac first (BOGO → Add Mac).")
                .type(.caption)
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Space.xxs)
        }
    }

    private func send(_ request: DemoRequest) {
        sent = request.rawValue
        Haptics.tick()
        Task {
            try? await Task.sleep(for: .seconds(3))
            bogo.standIn?.demo(request)
            if sent == request.rawValue { sent = nil }
        }
    }
}
#endif

#Preview {
    BridgeSettings()
}
