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
            VStack(alignment: .leading, spacing: Space.xl) {
                HomeHeader(approver: approver, waiting: live.count)
                ForEach(stale) { mac in
                    Button(action: addMac) {
                        HStack(spacing: Space.m) {
                            Tile(symbol: "faceid", size: 44, tint: Ink.claim, wash: Ink.claimWash)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add \(mac.name) again").type(.headline).foregroundStyle(Ink.primary)
                                Text("Face ID changed, so approvals from this iPhone stopped working.")
                                    .type(.label)
                                    .foregroundStyle(Ink.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.tertiary)
                        }
                        .card(padding: Space.m)
                    }
                    .buttonStyle(PressableStyle())
                }
                if !live.isEmpty {
                    VStack(spacing: Space.m) {
                        ForEach(live) { entry in
                            Button { section.reviewing = entry.primary.id } label: {
                                PendingCard(entry: entry, approver: approver, prominent: entry.id == live.first?.id)
                            }
                            .buttonStyle(PressableStyle())
                            .matchedTransitionSource(id: entry.primary.id, in: zoom)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity.combined(with: .scale(scale: 0.96))))
                        }
                    }
                } else if stale.isEmpty {
                    EmptyHome(connected: connected, addMac: addMac)
                        .transition(.opacity)
                }
                if !ended.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("Ended")
                        VStack(spacing: 0) {
                            ForEach(Array(ended.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Hairline().padding(.leading, 60) }
                                Button { section.reviewing = entry.primary.id } label: {
                                    ActivityRow(record: entry.primary, approver: approver, ended: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Space.m)
                        .card(padding: 0, radius: Radius.inner + 4)
                    }
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("Recent")
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { Hairline().padding(.leading, 60) }
                                Button { section.reviewing = record.id } label: {
                                    ActivityRow(record: record, approver: approver, ended: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Space.m)
                        .card(padding: 0, radius: Radius.inner + 4)
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
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .center) {
                HStack(spacing: Space.xs) {
                    BogoMark(size: 26)
                    Text("BOGO").type(.headline).tracking(1.2).foregroundStyle(Ink.primary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("BOGO")
                Spacer()
                NavigationLink(value: MacsRoute()) { MacChip(macs: approver.macs) }
                    .buttonStyle(PressableStyle())
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
        .padding(.top, Space.xs)
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
        return approver.macs.contains { $0.state == .active } ? "Nothing is waiting for you." : "Connect a Mac to get started."
    }
}

struct MacChip: View {
    let macs: [MacRecord]

    var body: some View {
        let active = macs.filter { $0.state == .active }
        HStack(spacing: 7) {
            if active.isEmpty {
                Image(systemName: "laptopcomputer").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.secondary)
            } else {
                StatusDot(Ink.positive)
            }
            Text(label(active)).type(.label, weight: .medium).foregroundStyle(Ink.primary).lineLimit(1)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Ink.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 0.75))
        .accessibilityLabel(active.isEmpty ? "Macs, none connected" : "Macs, \(label(active)) connected")
    }

    private func label(_ active: [MacRecord]) -> String {
        if active.isEmpty { return "No Mac" }
        return active.count == 1 ? active[0].name : "\(active.count) Macs"
    }
}

struct PendingCard: View {
    let entry: InboxEntry
    let approver: PhoneApprover
    var prominent = true

    var body: some View {
        let record = entry.primary
        VStack(alignment: .leading, spacing: Space.m) {
            if let request = record.request {
                let review = Review(request)
                HStack(spacing: Space.xs) {
                    Monogram(request.agentName, size: 20)
                    Text(Formatting.visible(request.agentName)).type(.label, weight: .semibold).foregroundStyle(Ink.primary).lineLimit(1)
                    Text("· " + Formatting.ago(record.receivedMs)).type(.label).foregroundStyle(Ink.tertiary).lineLimit(1)
                    Spacer(minLength: Space.xs)
                    if entry.count > 1 {
                        Text("×\(entry.count)")
                            .type(.caption, weight: .semibold)
                            .monospacedDigit()
                            .foregroundStyle(Ink.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Ink.raised, in: Capsule())
                            .accessibilityLabel("\(entry.count) identical requests")
                    }
                    if let expires = request.expires {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Label(Formatting.remaining(expires, now: context.date), systemImage: "timer")
                                .type(.caption, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(Ink.claim)
                        }
                    }
                }
                HStack(alignment: .center, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(Formatting.visible(review.title))
                            .type(.headline)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(review.subtitle.map { Formatting.visible($0) } ?? Formatting.via(review))
                            .type(.label)
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let image = review.image {
                        PictureThumb(link: image, size: 76)
                    } else {
                        Tile(symbol: Formatting.symbol(review), size: 52)
                    }
                }
                if !review.warnings.isEmpty {
                    Label("Reason mentions a different amount", systemImage: "exclamationmark.triangle.fill")
                        .type(.caption, weight: .semibold)
                        .foregroundStyle(Ink.claim)
                }
            } else {
                HStack(spacing: Space.m) {
                    Tile(symbol: "exclamationmark.triangle.fill", size: 52, tint: Ink.claim, wash: Ink.claimWash)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unreadable request").type(.headline).foregroundStyle(Ink.primary)
                        Text((approver.mac(record.bogoID)?.name ?? "Unknown Mac") + " · can’t be approved").type(.label).foregroundStyle(Ink.secondary)
                    }
                }
            }
            HStack(alignment: .center) {
                if let price = record.request.flatMap({ Review($0).price }), case .money(let amount, _) = price.value {
                    let parts = PriceView.split(amount)
                    Text("\(Text(parts.main))\(Text(parts.minor).foregroundStyle(Ink.secondary))")
                        .type(.title2)
                        .monospacedDigit()
                        .foregroundStyle(Ink.primary)
                } else if let facts = record.request.map({ PendingCard.facts(Review($0)) }), !facts.isEmpty {
                    Text(facts)
                        .type(.label, weight: .medium)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s)
                HStack(spacing: 6) {
                    Text("Review").type(.label, weight: .semibold)
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(prominent ? Ink.inverse : Ink.primary)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(prominent ? Ink.primary : Ink.raised, in: Capsule())
                .accessibilityHidden(true)
            }
        }
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the request to approve or deny")
    }

    static func facts(_ review: Review) -> String {
        review.details.prefix(2).compactMap { highlight -> String? in
            switch highlight.value {
            case .text(.string(let text)) where !text.isEmpty && !text.contains("\n"): return text
            case .text(.number(let text)): return text
            default: return nil
            }
        }.joined(separator: " · ")
    }
}

struct EmptyHome: View {
    let connected: Bool
    let addMac: () -> Void
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.xl) {
            ZStack {
                ForEach(0..<3) { ring in
                    Circle()
                        .strokeBorder(Ink.primary.opacity(0.06 - Double(ring) * 0.015), lineWidth: 1)
                        .frame(width: 96 + CGFloat(ring) * 52, height: 96 + CGFloat(ring) * 52)
                        .scaleEffect(breathe ? 1.03 : 0.98)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 3.2).repeatForever().delay(Double(ring) * 0.3), value: breathe)
                }
                Circle().fill(Ink.surface).frame(width: 88, height: 88).shadow(color: Ink.shadow, radius: 14, y: 6)
                Image(systemName: connected ? "checkmark.shield" : "laptopcomputer.and.iphone")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Ink.primary)
            }
            .frame(height: 210)
            .accessibilityHidden(true)
            VStack(spacing: Space.xs) {
                if !connected {
                    Text("Connect your Mac")
                        .type(.title2)
                        .foregroundStyle(Ink.primary)
                }
                Text(connected ? AttributedString("When an agent wants to spend money or act for you, it asks here first.")
                     : AttributedString("Agents on your Mac ask this iPhone before a protected tool runs. On the Mac, run ") + Formatting.code("bogo approver add") + AttributedString("."))
                    .type(.callout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            if !connected {
                Button("Add Mac", action: addMac)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .onAppear { breathe = true }
    }
}
