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
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Activity").type(.title).foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
                    Text(summary(records)).type(.callout).foregroundStyle(Ink.secondary)
                }
                .padding(.top, Space.xs)
                if records.isEmpty {
                    VStack(spacing: Space.m) {
                        Tile(symbol: "clock.arrow.circlepath", size: 64, tint: Ink.secondary)
                        Text("No activity yet").type(.title2).foregroundStyle(Ink.primary)
                        Text("Requests you approve or deny are kept here, like a statement.")
                            .type(.callout)
                            .foregroundStyle(Ink.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.huge)
                }
                ForEach(days, id: \.title) { day in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow(day.title)
                        VStack(spacing: 0) {
                            ForEach(Array(day.records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { Hairline().padding(.leading, 60) }
                                NavigationLink(value: record.id) {
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
        }
        .scrollIndicators(.hidden)
        .canvas()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func summary(_ records: [RequestRecord]) -> String {
        let approved = records.filter { Formatting.history($0).mark == .approved }.count
        let denied = records.filter { Formatting.history($0).mark == .denied }.count
        if records.isEmpty { return "Every decision you make lands here." }
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

    var body: some View {
        let history = Formatting.history(record)
        let review = record.request.map(Review.init)
        HStack(spacing: Space.s) {
            ZStack(alignment: .bottomTrailing) {
                if let review, let image = review.image {
                    PictureThumb(link: image, size: 44)
                } else if let review {
                    Tile(symbol: Formatting.symbol(review), size: 44)
                } else {
                    Tile(symbol: "exclamationmark.triangle", size: 44, tint: Ink.claim, wash: Ink.claimWash)
                }
                if !ended { badge(history.mark).offset(x: 4, y: 4) }
            }
            .opacity(ended ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(review.map { Formatting.visible($0.title) } ?? AttributedString("Unreadable request"))
                    .type(.callout, weight: .semibold)
                    .foregroundStyle(ended ? Ink.secondary : Ink.primary)
                    .lineLimit(1)
                Text(detail(review, history.text))
                    .type(.caption)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.xs)
            VStack(alignment: .trailing, spacing: 2) {
                if let review, let price = review.price, case .money(let amount, _) = price.value {
                    Text(amount.formatted)
                        .type(.callout, weight: .semibold)
                        .monospacedDigit()
                        .strikethrough(history.mark != .approved || ended, color: Ink.tertiary)
                        .foregroundStyle(history.mark == .approved && !ended ? Ink.primary : Ink.tertiary)
                }
                Text(Formatting.when(Date(timeIntervalSince1970: TimeInterval(record.changedMs) / 1000)))
                    .type(.caption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ review: Review?, _ status: String) -> AttributedString {
        let state = ended ? Formatting.status(record, now: UInt64(Date().timeIntervalSince1970 * 1000)) ?? status : status
        guard let review else { return AttributedString((approver.mac(record.bogoID)?.name ?? "Unknown Mac") + " · " + state) }
        return Formatting.visible(review.request.agentName) + AttributedString(" · " + state)
    }

    private func badge(_ mark: Formatting.Mark) -> some View {
        let (symbol, tint): (String, Color) = switch mark {
        case .approved: ("checkmark", Ink.positive)
        case .denied: ("xmark", Ink.negative)
        case .ended: ("minus", Ink.tertiary)
        case .paused: ("pause.fill", Ink.tertiary)
        }
        return Image(systemName: symbol)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(Ink.surface, lineWidth: 2))
            .accessibilityHidden(true)
    }
}
