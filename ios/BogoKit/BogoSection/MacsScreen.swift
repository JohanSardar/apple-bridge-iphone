import BogoModel
import BogoRelay
import SwiftUI

struct MacsScreen: View {
    let approver: PhoneApprover
    var addMac: (() -> Void)?
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Macs").type(.title).foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
                    Text("Agents on these Macs ask this iPhone before a protected tool runs.")
                        .type(.callout)
                        .foregroundStyle(Ink.secondary)
                }
                if approver.macs.isEmpty {
                    Text(AttributedString("No Macs yet. On your Mac, run ") + Formatting.code("bogo approver add") + AttributedString(", then add it here."))
                        .type(.body)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        Hairline()
                        ForEach(approver.macs) { mac in
                            NavigationLink {
                                MacDetail(approver: approver, id: mac.bogoID)
                            } label: {
                                MacRow(mac: mac)
                            }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }
                }
                Button("Add Mac") {
                    if let addMac { addMac() } else { adding = true }
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
            VStack(alignment: .leading, spacing: 3) {
                Text(mac.name).type(.headline).foregroundStyle(Ink.primary)
                Text(MacRow.status(mac)).type(.label).foregroundStyle(MacRow.tint(mac))
            }
            Spacer()
            Chevron()
        }
        .padding(.vertical, Space.m)
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
        case .waiting, .removed: return Ink.secondary
        case .needsReRegistration: return Ink.warning
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
                VStack(alignment: .leading, spacing: Space.xxl) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(mac.name).type(.title).foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
                        Text(MacRow.status(mac)).type(.callout).foregroundStyle(MacRow.tint(mac))
                    }
                    .padding(.top, Space.xs)
                    VStack(spacing: 0) {
                        DetailRow(Text("Added")) {
                            Text(Date(timeIntervalSince1970: TimeInterval(mac.addedMs) / 1000).formatted(date: .abbreviated, time: .shortened))
                        }
                        DetailRow(Text("Requests")) {
                            Text("\(approver.records.filter { $0.bogoID == mac.bogoID && $0.receivedMs > 0 }.count)").monospacedDigit()
                        }
                        DetailRow(Text("Approval key")) { Text("Face ID protected") }
                    }
                    if mac.state != .removed {
                        VStack(spacing: Space.s) {
                            Button("Remove Mac", role: .destructive) { removing = true }
                                .buttonStyle(DestructiveButtonStyle())
                            Text("This iPhone stops approving requests from \(mac.name). You can add it again later.")
                                .type(.caption)
                                .foregroundStyle(Ink.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
