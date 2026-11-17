import BogoModel
import BogoRelay
import SwiftUI

struct ActivityTab: View {
    let section: BogoSection

    var body: some View {
        NavigationStack {
            HistoryScreen(approver: section.approver)
                .navigationDestination(for: String.self) { id in
                    ReviewScreen(approver: section.approver, id: id)
                }
        }
    }
}

struct HistoryScreen: View {
    let approver: PhoneApprover

    var body: some View {
        let records = Inbox.history(approver.shown)
        let days = HistoryScreen.days(records)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Activity").type(.title).foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
                    Text(summary(records)).type(.callout).foregroundStyle(Ink.secondary)
                }
                .padding(.top, Space.s)
                ForEach(days, id: \.title) { day in
                    RowSection(day.title) {
                        ForEach(Array(day.records.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { Hairline() }
                            NavigationLink(value: record.id) {
                                ActivityRow(record: record, approver: approver, ended: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xxl)
        }
        .scrollIndicators(.hidden)
        .canvas()
        .toolbar(.hidden, for: .navigationBar)
        .statusScrim()
    }

    private func summary(_ records: [RequestRecord]) -> String {
        let approved = records.filter { Formatting.history($0).mark == .approved }.count
        let denied = records.filter { Formatting.history($0).mark == .denied }.count
        if records.isEmpty { return "Requests you approve or deny are kept here." }
        return "\(approved) approved · \(denied) denied"
    }

    static func days(_ records: [RequestRecord]) -> [(title: String, records: [RequestRecord])] {
        var result: [(title: String, records: [RequestRecord])] = []
        let calendar = Calendar.current
        for record in records {
            let date = Date(timeIntervalSince1970: TimeInterval(record.changedMs) / 1000)
            let title = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday" : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            if result.last?.title == title { result[result.count - 1].records.append(record) } else { result.append((title, [record])) }
        }
        return result
    }
}

struct ActivityRow: View {
    let record: RequestRecord
    let approver: PhoneApprover
    let ended: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let history = Formatting.history(record)
        let review = record.request.map(Review.init)
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs)) : AnyLayout(HStackLayout(alignment: .center, spacing: Space.s))
        HStack(alignment: .center, spacing: Space.s) {
            layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(review.map { Formatting.visible(Formatting.title($0)) } ?? AttributedString("Unreadable request"))
                    .type(.callout, weight: .medium)
                    .foregroundStyle(ended ? Ink.secondary : Ink.primary)
                    .lineLimit(2)
                Text(detail(review, history.text))
                    .type(.label)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(2)
            }
            if !stacked { Spacer(minLength: Space.s) }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                if let review, let price = review.price, case .money(let amount, _) = price.value {
                    Text(amount.formatted)
                        .type(.callout, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(history.mark == .approved && !ended ? Ink.primary : Ink.tertiary)
                }
                Text(Formatting.when(Date(timeIntervalSince1970: TimeInterval(record.changedMs) / 1000)))
                    .type(.label)
                    .foregroundStyle(Ink.tertiary)
            }
            .fixedSize()
            }
            Spacer(minLength: 0)
            Chevron()
        }
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ review: Review?, _ status: String) -> AttributedString {
        let state = ended ? Formatting.status(record, now: UInt64(Date().timeIntervalSince1970 * 1000)) ?? status : status
        let split = state.range(of: " · ")
        var outcome = AttributedString(split.map { String(state[..<$0.lowerBound]) } ?? state)
        if !ended {
            switch Formatting.history(record).mark {
            case .approved: outcome.foregroundColor = Ink.positive
            case .denied: outcome.foregroundColor = Ink.negative
            case .ended, .paused: break
            }
        }
        if let split { outcome += AttributedString(String(state[split.lowerBound...])) }
        guard let review else { return AttributedString((approver.mac(record.bogoID)?.name ?? "Unknown Mac") + " · ") + outcome }
        return Formatting.visible(review.request.agentName) + AttributedString(" · ") + outcome
    }
}
