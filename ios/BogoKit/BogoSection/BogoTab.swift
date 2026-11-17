import BogoModel
import BogoRelay
import SwiftUI

struct BogoHome: View {
    @Bindable var section: BogoSection
    @Environment(\.scenePhase) private var scenePhase
    @State private var addingMac = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            HomeScreen(section: section, zoom: zoom, addMac: { addingMac = true })
                .navigationDestination(item: $section.reviewing) { id in
                    ReviewScreen(approver: section.approver, id: id)
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
                .navigationDestination(for: MacsRoute.self) { _ in
                    MacsScreen(approver: section.approver, addMac: { addingMac = true })
                }
        }
        .sheet(isPresented: $addingMac) {
            AddMacScreen(approver: section.approver)
        }
        .task { await section.sceneBecameActive() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await section.sceneBecameActive() } }
        }
    }
}

struct MacsRoute: Hashable {}

struct HomeScreen: View {
    @Bindable var section: BogoSection
    let zoom: Namespace.ID
    let addMac: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let approver = section.approver
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        let entries = Inbox.entries(approver.shown, now: now)
        let live = entries.filter(\.live)
        let ended = entries.filter { !$0.live }
        let stale = approver.macs.filter { $0.state == .needsReRegistration }
        let connected = approver.macs.contains { $0.state == .active }
        let recent = Array(Inbox.history(approver.shown).prefix(3))
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                HomeHeader(approver: approver, waiting: live.count)
                if !stale.isEmpty {
                    VStack(spacing: 0) {
                        Hairline()
                        ForEach(stale) { mac in
                            Button(action: addMac) {
                                HStack(spacing: Space.s) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Add \(mac.name) again").type(.headline).foregroundStyle(Ink.primary)
                                        Text("Face ID changed, so approvals from this iPhone stopped working.")
                                            .type(.label)
                                            .foregroundStyle(Ink.warning)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Chevron()
                                }
                                .padding(.vertical, Space.m)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }
                }
                if !live.isEmpty {
                    VStack(spacing: 0) {
                        Hairline()
                        ForEach(live) { entry in
                            Button { section.reviewing = entry.primary.id } label: {
                                PendingRow(entry: entry, approver: approver)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: entry.primary.id, in: zoom)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                            Hairline()
                        }
                    }
                } else if stale.isEmpty && !connected {
                    EmptyHome(addMac: addMac)
                        .transition(.opacity)
                }
                if !ended.isEmpty {
                    RowSection("Ended") {
                        ForEach(Array(ended.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Hairline() }
                            Button { section.reviewing = entry.primary.id } label: {
                                ActivityRow(record: entry.primary, approver: approver, ended: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !recent.isEmpty {
                    RowSection("Recent") {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { Hairline() }
                            Button { section.reviewing = record.id } label: {
                                ActivityRow(record: record, approver: approver, ended: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xxl)
            .animation(Motion.respecting(reduceMotion, Motion.standard), value: live.map(\.id))
        }
        .scrollIndicators(.hidden)
        .canvas()
        .refreshable { await section.sceneBecameActive() }
        .toolbar(.hidden, for: .navigationBar)
        .statusScrim()
        .onChange(of: live.map(\.id)) { old, new in
            if new.count > old.count { Haptics.soft() }
        }
    }
}

struct HomeHeader: View {
    let approver: PhoneApprover
    let waiting: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(alignment: .firstTextBaseline) {
                Text("BOGO").type(.headline).foregroundStyle(Ink.primary)
                Spacer()
                NavigationLink(value: MacsRoute()) { MacStatusLink(macs: approver.macs) }
                    .buttonStyle(.plain)
            }
            if waiting > 0 || approver.macs.contains(where: { $0.state == .active }) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(headline)
                        .type(.title)
                        .foregroundStyle(Ink.primary)
                        .contentTransition(.numericText())
                        .accessibilityAddTraits(.isHeader)
                    Text(subhead).type(.callout).foregroundStyle(Ink.secondary)
                }
            }
        }
        .padding(.top, Space.s)
        .animation(Motion.standard, value: waiting)
    }

    private var headline: String {
        switch waiting {
        case 0: return "All clear"
        case 1: return "1 request waiting"
        default: return "\(waiting) requests waiting"
        }
    }

    private var subhead: String {
        if waiting > 0 { return "Nothing runs until you approve." }
        return "When an agent wants to spend money or act for you, it asks here first."
    }
}

struct MacStatusLink: View {
    let macs: [MacRecord]

    var body: some View {
        let active = macs.filter { $0.state == .active }
        HStack(spacing: 6) {
            Text(label(active)).type(.callout).foregroundStyle(Ink.secondary).lineLimit(1)
            Chevron()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active.isEmpty ? "Macs, none connected" : "Macs, \(label(active)) connected")
        .accessibilityAddTraits(.isButton)
    }

    private func label(_ active: [MacRecord]) -> String {
        if active.isEmpty { return "No Mac" }
        return active.count == 1 ? active[0].name : "\(active.count) Macs"
    }
}

struct PendingRow: View {
    let entry: InboxEntry
    let approver: PhoneApprover
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let record = entry.primary
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs)) : AnyLayout(HStackLayout(alignment: .center, spacing: Space.s))
        HStack(alignment: .center, spacing: Space.s) {
            layout {
            if let request = record.request {
                let review = Review(request)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Formatting.visible(Formatting.title(review)))
                        .type(.headline)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(stacked ? 4 : 2)
                        .multilineTextAlignment(.leading)
                    Text(byline(request, record))
                        .type(.label)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(2)
                    if !review.warnings.isEmpty {
                        Text("Amount differs from the reason")
                            .type(.label, weight: .medium)
                            .foregroundStyle(Ink.warning)
                    }
                }
                if !stacked { Spacer(minLength: Space.s) }
                VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                    if let price = review.price, case .money(let amount, _) = price.value {
                        Text(amount.formatted).type(.headline).monospacedDigit().foregroundStyle(Ink.primary)
                    }
                    if let expires = request.expires {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Formatting.remaining(expires, now: context.date) + " left")
                                .type(.label)
                                .monospacedDigit()
                                .foregroundStyle(Ink.tertiary)
                        }
                    }
                }
                .fixedSize()
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Unreadable request").type(.headline).foregroundStyle(Ink.primary)
                    Text((approver.mac(record.bogoID)?.name ?? "Unknown Mac") + " · can’t be approved").type(.label).foregroundStyle(Ink.secondary)
                }
            }
            }
            Spacer(minLength: 0)
            Chevron()
        }
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the request to approve or deny")
    }

    private func byline(_ request: ApprovalRequest, _ record: RequestRecord) -> AttributedString {
        var line = Formatting.visible(request.agentName) + AttributedString(" · " + Formatting.ago(record.receivedMs))
        if entry.count > 1 { line += AttributedString(" · \(entry.count) identical") }
        return line
    }
}

struct EmptyHome: View {
    let addMac: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Connect your Mac").type(.title).foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
                Text(AttributedString("Agents on your Mac ask this iPhone before a protected tool runs. On the Mac, run ") + Formatting.code("bogo approver add") + AttributedString("."))
                    .type(.body)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Add Mac", action: addMac)
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
