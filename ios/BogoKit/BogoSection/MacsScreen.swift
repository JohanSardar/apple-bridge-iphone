import BogoModel
import BogoRelay
import SwiftUI

struct MacsScreen: View {
    let approver: PhoneApprover
    var addMac: (() -> Void)?
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Macs").type(.title).foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
                    Text("Agents on these Macs ask this iPhone before a protected tool runs.")
                        .type(.callout)
                        .foregroundStyle(Ink.secondary)
                }
                if approver.macs.isEmpty {
                    VStack(spacing: Space.m) {
                        Tile(symbol: "laptopcomputer", size: 64, tint: Ink.secondary)
                        Text("No Macs yet").type(.title2).foregroundStyle(Ink.primary)
                        Text(AttributedString("On your Mac, run ") + Formatting.code("bogo approver add") + AttributedString(", then add it here."))
                            .type(.callout)
                            .foregroundStyle(Ink.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.xxl)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(approver.macs.enumerated()), id: \.element.id) { index, mac in
                            if index > 0 { Hairline().padding(.leading, 60) }
                            NavigationLink {
                                MacDetail(approver: approver, id: mac.bogoID)
                            } label: {
                                MacRow(mac: mac)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .card(padding: 0, radius: Radius.inner + 4)
                }
                Button {
                    if let addMac { addMac() } else { adding = true }
                } label: {
                    Label("Add Mac", systemImage: "plus")
                }
                .buttonStyle(approver.macs.isEmpty ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xxl)
        }
        .canvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $adding) { AddMacScreen(approver: approver) }
    }
}

struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<Style: ButtonStyle>(_ style: Style) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

struct MacRow: View {
    let mac: MacRecord

    var body: some View {
        HStack(spacing: Space.s) {
            Tile(symbol: "laptopcomputer", size: 44, tint: mac.state == .active ? Ink.primary : Ink.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name).type(.callout, weight: .semibold).foregroundStyle(Ink.primary)
                HStack(spacing: 6) {
                    Circle().fill(MacRow.tint(mac)).frame(width: 6, height: 6)
                    Text(MacRow.status(mac)).type(.caption).foregroundStyle(mac.state == .needsReRegistration ? Ink.claim : Ink.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.tertiary)
        }
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func status(_ mac: MacRecord) -> String {
        switch mac.state {
        case .active: return "Connected"
        case .waiting: return "Waiting for the Mac to confirm"
        case .needsReRegistration: return "Face ID changed · add again"
        case .removed: return "Removing · waiting for the Mac"
        }
    }

    static func tint(_ mac: MacRecord) -> Color {
        switch mac.state {
        case .active: return Ink.positive
        case .waiting, .removed: return Ink.tertiary
        case .needsReRegistration: return Ink.claim
        }
    }
}

struct MacDetail: View {
    let approver: PhoneApprover
    let id: Data
    @Environment(\.dismiss) private var dismiss
    @State private var removing = false

    var body: some View {
        if let mac = approver.mac(id) {
            ScrollView {
                VStack(spacing: Space.xl) {
                    VStack(spacing: Space.s) {
                        Tile(symbol: "laptopcomputer", size: 76)
                        Text(mac.name).type(.title).foregroundStyle(Ink.primary)
                        HStack(spacing: 6) {
                            Circle().fill(MacRow.tint(mac)).frame(width: 7, height: 7)
                            Text(MacRow.status(mac)).type(.label, weight: .medium).foregroundStyle(Ink.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Ink.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 0.75))
                    }
                    .padding(.top, Space.l)
                    VStack(spacing: 0) {
                        DetailRow(Text("Added")) {
                            Text(Date(timeIntervalSince1970: TimeInterval(mac.addedMs) / 1000).formatted(date: .abbreviated, time: .shortened))
                        }
                        Hairline()
                        DetailRow(Text("Requests")) {
                            Text("\(approver.records.filter { $0.bogoID == mac.bogoID && $0.receivedMs > 0 }.count)").monospacedDigit()
                        }
                        Hairline()
                        DetailRow(Text("Approval key")) { Text("Face ID protected") }
                    }
                    .padding(.horizontal, Space.l)
                    .card(padding: 0, radius: Radius.inner + 4)
                    if mac.state != .removed {
                        VStack(spacing: Space.s) {
                            Button("Remove Mac", role: .destructive) { removing = true }
                                .buttonStyle(DestructiveButtonStyle())
                            Text("This iPhone stops approving requests from \(mac.name). You can add it again later.")
                                .type(.caption)
                                .foregroundStyle(Ink.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xxl)
            }
            .canvas()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .confirmationDialog("Remove \(mac.name)?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove Mac", role: .destructive) {
                    approver.remove(mac)
                    dismiss()
                }
            }
        }
    }
}
