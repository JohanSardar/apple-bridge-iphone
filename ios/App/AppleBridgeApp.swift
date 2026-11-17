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
            VStack(alignment: .leading, spacing: Space.xxl) {
                Text("Settings").type(.title).foregroundStyle(Ink.primary).padding(.top, Space.s).accessibilityAddTraits(.isHeader)
                RowSection("BOGO") {
                    NavigationLink { bogo.macs } label: {
                        SettingsRow(title: "Macs", detail: "Where your agents run")
                    }
                }
                RowSection("Apple Bridge") {
                    NavigationLink { PairingScreen(state: pairing) } label: {
                        SettingsRow(title: "Gateway pairing", detail: pairing.status)
                    }
                }
                RowSection("Capabilities") {
                    ForEach(Array(Capabilities.all.enumerated()), id: \.element.id) { index, capability in
                        if index > 0 { Hairline() }
                        NavigationLink {
                            if capability.id == "screentime" {
                                ScreenTimeScreen()
                            } else {
                                CapabilityScreen(capability: capability)
                            }
                        } label: {
                            SettingsRow(title: capability.title, detail: "\(capability.permission) · No activity")
                        }
                    }
                }
                RowSection("Support") {
                    NavigationLink { DiagnosticsScreen(pairing: pairing) } label: {
                        SettingsRow(title: "Diagnostics", detail: "Version, gateway and push delivery")
                    }
                }
                #if DEBUG
                DemoControls(bogo: bogo)
                #endif
                Text("Apple Bridge \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · BOGO")
                    .type(.caption)
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xxl)
        }
        .scrollIndicators(.hidden)
        .canvas()
        .toolbar(.hidden, for: .navigationBar)
        .statusScrim()
    }
}

struct SettingsRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).type(.callout, weight: .medium).foregroundStyle(Ink.primary)
                Text(detail).type(.label).foregroundStyle(Ink.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: Space.xs)
            Chevron()
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DiagnosticsScreen: View {
    @Bindable var pairing: PairingState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(spacing: 0) {
                    DetailRow(Text("Version")) { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") }
                    DetailRow(Text("Gateway")) { Text(pairing.status) }
                    DetailRow(Text("Capabilities")) { Text(String(Capabilities.all.count)).monospacedDigit() }
                    DetailRow(Text("Last command")) { Text(PushDelivery.shared.lastResult) }
                    DetailRow(Text("Push delivery")) { Text(PushDelivery.shared.status) }
                    DetailRow(Text("Push wakes")) { Text(String(PushDelivery.shared.wakeCount)).monospacedDigit() }
                }
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
            RowSection("Demo") {
                Toggle(isOn: $quiet) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Quiet stand-in Mac").type(.callout, weight: .medium).foregroundStyle(Ink.primary)
                        Text("Add Mac sends no sample requests").type(.label).foregroundStyle(Ink.secondary)
                    }
                }
                .tint(Ink.positive)
                .padding(.vertical, Space.m)
                .onChange(of: quiet) { _, value in StandInMacLink.quiet = value }
                ForEach(DemoRequest.allCases, id: \.self) { request in
                    Hairline()
                    Button { send(request) } label: {
                        HStack {
                            Text(request.title).type(.callout, weight: .medium).foregroundStyle(Ink.primary)
                            Spacer()
                            Text(sent == request.rawValue ? "Arrives in 3 s" : "Send").type(.label).foregroundStyle(Ink.secondary)
                        }
                        .padding(.vertical, Space.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(bogo.standIn?.connected == true ? "Debug builds only. Requests come from the stand-in Mac, 3 seconds after you tap." : "Debug builds only. Add the Stand-in Mac first (BOGO → Add Mac).")
                .type(.caption)
                .foregroundStyle(Ink.tertiary)
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

let ciMustFail: Int = "not a number"
