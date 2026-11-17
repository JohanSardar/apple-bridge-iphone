import BogoModel
import BogoRelay
import SwiftUI

struct AllDetails: View {
    let record: RequestRecord
    let macName: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if let request = record.request {
                        let review = Review(request)
                        Text("This is the exact request you sign, every value as the agent sent it.")
                            .type(.callout)
                            .foregroundStyle(Ink.secondary)
                        section("Will execute, exactly") { WillExecute(review: review) }
                        section("Agent’s reason, not verified") { ExactReason(request: request) }
                        section("Request") { RequestFacts(record: record, request: request, macName: macName) }
                        if !request.hints.isEmpty {
                            section("Display hints") { HintList(request: request) }
                        }
                    } else {
                        section("Unreadable request") {
                            VStack(alignment: .leading, spacing: 0) {
                                DetailRow(Text("From")) { Text(macName ?? "Unknown Mac") }
                                Hairline()
                                DetailRow(Text("Size")) { Text("\(record.bytes.count) bytes") }
                            }
                        }
                    }
                }
                .padding(Space.gutter)
            }
            .canvas()
            .navigationTitle("All details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        RowSection(title) {
            content()
        }
    }
}

struct WillExecute: View {
    let review: Review
    @State private var unfolded: Set<Int> = []

    var body: some View {
        let request = review.request
        VStack(alignment: .leading, spacing: 0) {
            DetailRow(Text("Upstream")) { Text(Formatting.visible(request.upstream)) }
            Hairline()
            DetailRow(Text("Tool")) { Text(Formatting.visible(request.tool)).monospaced() }
            Hairline()
            DetailRow(Text("Requested by")) { Text(Formatting.visible(request.agentName)) }
            Hairline()
            if let rows = review.arguments {
                Text("Arguments")
                    .type(.label, weight: .semibold)
                    .foregroundStyle(Ink.secondary)
                    .padding(.top, Space.m)
                    .padding(.bottom, Space.xxs)
                if rows.isEmpty {
                    Text("Empty arguments { }").type(.callout).foregroundStyle(Ink.secondary).padding(.vertical, Space.s)
                }
                ForEach(rows.filter { $0.foldedInto.map(unfolded.contains) ?? true }) { row in
                    if let fold = row.fold {
                        FoldRow(fold: fold, depth: row.depth, open: unfolded.contains(row.id)) {
                            withAnimation(Motion.snappy) {
                                if unfolded.contains(row.id) { unfolded.remove(row.id) } else { unfolded.insert(row.id) }
                            }
                        }
                    } else {
                        ArgumentRowView(row: row)
                    }
                }
            } else {
                Text("No arguments sent").type(.callout).foregroundStyle(Ink.secondary).padding(.vertical, Space.s)
            }
        }
        .padding(.bottom, Space.xs)
    }
}

struct FoldRow: View {
    let fold: Review.EmptyFold
    let depth: Int
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .center, spacing: Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(fold.labels.count) empty \(fold.items ? "items" : "fields")")
                        .type(.callout, weight: .medium)
                        .foregroundStyle(Ink.secondary)
                    if !open {
                        Text(Formatting.list(fold.labels))
                            .type(.caption)
                            .foregroundStyle(Ink.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Chevron()
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(depth) * 14)
        .accessibilityHint(open ? "Hides them" : "Shows them")
    }
}

struct ArgumentRowView: View {
    let row: Review.ArgumentRow

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    label
                    if let picture = row.picture {
                        PictureThumb(link: picture, size: 64).padding(.vertical, 2)
                    }
                    if let leaf = row.leaf {
                        Text(Formatting.value(leaf))
                            .type(multiline ? .mono : .callout)
                            .foregroundStyle(Ink.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    label
                    Spacer(minLength: 0)
                    if let leaf = row.leaf {
                        Text(Formatting.value(leaf))
                            .type(.callout)
                            .foregroundStyle(Ink.primary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    } else if let container = row.container {
                        Text(container.description).type(.callout).foregroundStyle(Ink.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, CGFloat(row.depth) * 14)
        .overlay(alignment: .leading) {
            if row.depth > 0 {
                Rectangle().fill(Ink.hairline).frame(width: 1).padding(.leading, CGFloat(row.depth) * 14 - 8)
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if let text = row.label {
            Text(Formatting.visible(text))
                .type(.callout, weight: row.highlighted ? .semibold : .regular)
                .foregroundStyle(row.highlighted ? Ink.primary : Ink.secondary)
        }
    }

    private var multiline: Bool {
        if case .string(let text)? = row.leaf { return text.contains("\n") }
        return false
    }

    private var stacked: Bool {
        if row.picture != nil { return true }
        let room = 34 - (row.label?.count ?? 0) - row.depth * 2
        switch row.leaf {
        case .string(let text)?: return multiline || text.count > min(24, room)
        case .number(let text)?: return text.count > min(20, room)
        default: return false
        }
    }
}

extension Review.Container {
    var description: String {
        switch self {
        case .object(let count): return count == 1 ? "1 field" : "\(count) fields"
        case .array(let count): return count == 1 ? "1 item" : "\(count) items"
        }
    }
}

struct ExactReason: View {
    let request: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let justification = request.justification {
                    if justification.isEmpty {
                        Text("Empty reason").foregroundStyle(Ink.secondary)
                    } else {
                        Text(Formatting.visible(justification, quoted: true)).foregroundStyle(Ink.primary).textSelection(.enabled)
                    }
                } else {
                    Text("No reason given").foregroundStyle(Ink.secondary)
                }
            }
            .type(.callout)
            .padding(.vertical, Space.s)
            Hairline()
            DetailRow(Text("Client")) {
                if let client = request.clientName { Text(Formatting.visible(client)) } else { Text("Not reported").foregroundStyle(Ink.secondary) }
            }
            Hairline()
            DetailRow(Text("Session")) { Text(request.sessionTag).monospaced() }
        }
    }
}

struct RequestFacts: View {
    let record: RequestRecord
    let request: ApprovalRequest
    let macName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailRow(Text("From")) { Text(macName ?? "Unknown Mac") }
            Hairline()
            DetailRow(Text("Created")) { Text(request.created.formatted(date: .abbreviated, time: .standard)) }
            Hairline()
            DetailRow(Text("Expires")) { Text(request.expires?.formatted(date: .abbreviated, time: .standard) ?? "When the agent stops waiting") }
            Hairline()
            DetailRow(Text("Request ID")) { Text(Hex.string(request.nonce.suffix(8))).monospaced() }
            Hairline()
            DetailRow(Text("Signed bytes")) { Text("\(record.bytes.count)").monospacedDigit() }
        }
    }
}

struct HintList: View {
    let request: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(request.hints.enumerated()), id: \.offset) { index, hint in
                if index > 0 { Hairline() }
                DetailRow(Text(Formatting.visible(Review.label(hint.path))).monospaced()) { Text(name(hint.format)) }
            }
        }
    }

    private func name(_ format: DisplayFormat) -> String {
        switch format {
        case .text: return "Detail"
        case .moneyMinor(let currency): return "Price · \(currency) minor units"
        case .title: return "Title"
        case .subtitle: return "Subtitle"
        case .image: return "Picture"
        }
    }
}
