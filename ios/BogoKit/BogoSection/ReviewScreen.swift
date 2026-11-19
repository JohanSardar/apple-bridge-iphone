import BogoModel
import BogoRelay
import SwiftUI

struct ReviewScreen: View {
    let approver: PhoneApprover
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var armedAt = Date.distantFuture
    @State private var armed = false
    @State private var busy = false
    @State private var denying = false
    @State private var pausing = false
    @State private var details = false
    @State private var problem: String?
    @State private var approved: ApprovedSummary?
    @State private var arrived = false
    @State private var refresh = 0

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            if let record = approver.record(id) {
                content(record, now: UInt64(Date().timeIntervalSince1970 * 1000))
            } else {
                Text("This request is no longer on this iPhone.").type(.body).foregroundStyle(Ink.secondary).padding(Space.gutter)
            }
            if let approved {
                ApprovedOverlay(summary: approved) { dismiss() }
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(approved != nil)
        .toolbar(approved == nil ? .visible : .hidden, for: .navigationBar)
        .onAppear {
            arm()
            withAnimation(Motion.respecting(reduceMotion, Motion.gentle).delay(0.05)) { arrived = true }
        }
        .onChange(of: id) { arm() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { arm() } }
        .task(id: armedAt) {
            let wait = armedAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled && armedAt != .distantFuture { armed = true }
        }
        .task(id: id) {
            guard let expires = approver.record(id)?.request?.expires else { return }
            let wait = expires.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait + 0.05)) }
            refresh += 1
        }
        .sheet(isPresented: $denying) {
            DenySheet(agent: approver.record(id)?.request?.agentName) { note in deny(note) }
        }
        .sheet(isPresented: $details) {
            if let record = approver.record(id) { AllDetails(record: record, macName: approver.mac(record.bogoID)?.name) }
        }
        .alert("Nothing was approved", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    @ViewBuilder
    private func content(_ record: RequestRecord, now: UInt64) -> some View {
        let open = record.deniable(at: now) && approved == nil
        let paused = approver.isPaused(record)
        let entry = Inbox.entries(approver.shown, now: now).first { $0.records.contains { $0.id == record.id } }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let status = Formatting.status(record, now: now), !record.phase.isPending || !open, approved == nil {
                    StatusLine(text: status, mark: Formatting.history(record).mark, pending: record.phase.isPending)
                        .padding(.bottom, Space.l)
                }
                if let request = record.request {
                    let review = Review(request)
                    ReviewSummary(review: review, received: record.receivedMs)
                        .offset(y: arrived ? 0 : 16)
                        .opacity(arrived ? 1 : 0)
                    Group {
                        Hairline().padding(.vertical, Space.xl)
                        ReasonSection(review: review)
                        Hairline().padding(.vertical, Space.xl)
                        DetailsSection(review: review, macName: approver.mac(record.bogoID)?.name,
                                       waiting: open ? (entry?.count ?? 1) : 1, showDetails: { details = true })
                    }
                    .offset(y: arrived ? 0 : 24)
                    .opacity(arrived ? 1 : 0)
                } else {
                    UnreadableSection(record: record, macName: approver.mac(record.bogoID)?.name)
                    Hairline().padding(.top, Space.xl)
                    AllDetailsRow(count: nil) { details = true }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xl)
            .id(refresh)
        }
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(record.request == nil ? "Unreadable request" : open ? "Review request" : "Request")
                    .type(.headline)
                    .foregroundStyle(Ink.primary)
            }
            if let request = record.request, open, !paused {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Pause \(request.agentName)", role: .destructive) { pausing = true }
                        Button("All details") { details = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .confirmationDialog("Pause \(record.request?.agentName ?? "this agent")?", isPresented: $pausing, titleVisibility: .visible) {
            Button("Pause Agent", role: .destructive) {
                approver.pause(record)
                dismiss()
            }
        } message: {
            Text("Its waiting requests end now, and BOGO refuses new ones until you un-pause it on the Mac.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if open && !paused {
                actions(record)
                    .offset(y: arrived ? 0 : 80)
                    .opacity(arrived ? 1 : 0)
            }
        }
    }

    private func actions(_ record: RequestRecord) -> some View {
        VStack(spacing: Space.xxs) {
            if record.request != nil {
                SlideToApprove(armed: armed, armDelay: TimeInterval(record.armDelayMs) / 1000, busy: busy) { approve(record) }
            }
            Button(record.request == nil ? "Deny request" : "Deny") { denying = true }
                .buttonStyle(QuietButtonStyle(tint: record.request == nil ? Ink.negative : Ink.secondary))
                .disabled(busy)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.m)
        .frame(maxWidth: .infinity)
        .background(Ink.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    private func arm() {
        let delay = approver.record(id)?.armDelayMs ?? 2000
        armed = false
        armedAt = Date().addingTimeInterval(TimeInterval(delay) / 1000)
    }

    private func approve(_ record: RequestRecord) {
        busy = true
        Task {
            let result = await approver.approve(record)
            switch result {
            case .decided:
                Haptics.success()
                let review = record.request.map(Review.init)
                withAnimation(Motion.respecting(reduceMotion, Motion.standard)) {
                    approved = ApprovedSummary(title: review.map(Formatting.title) ?? "Request",
                                               price: review?.price.flatMap { if case .money(let amount, _) = $0.value { return amount } else { return nil } },
                                               mac: approver.mac(record.bogoID)?.name ?? "your Mac")
                }
                busy = false
            case .nothingSigned(let reason):
                busy = false
                problem = reason
            }
        }
    }

    private func deny(_ note: String) {
        guard let record = approver.record(id) else { return }
        denying = false
        if case .nothingSigned(let reason) = approver.deny(record, note: note) {
            problem = reason
        } else {
            Haptics.soft()
            dismiss()
        }
    }
}

struct ApprovalGroupReview: View {
    let approver: PhoneApprover
    let anchor: RequestRecord
    let group: ApprovalGroup
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: String?
    @State private var armed = false
    @State private var busy = false
    @State private var problem: String?
    @State private var details: RequestRecord?
    @State private var denying: RequestRecord?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = UInt64(context.date.timeIntervalSince1970 * 1000)
            let members = approver.groupMembers(anchor)
            let winner = members.first(where: \.groupSelectionConfirmed)
            let submitted = members.first { $0.phase == .sent(.approved) }
            let closed = winner != nil || members.contains(where: \.wasSuperseded)
            let live = closed ? [] : members.filter { $0.approvable(at: now) && !approver.isPaused($0) }
            let selected = live.first { $0.id == selection }
            let visible = winner.map { [$0] } ?? (closed ? [] : submitted.map { [$0] } ?? live)
            scroll(visible, selected: selected, winner: winner, submitted: closed ? nil : submitted, closed: closed)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let selected, winner == nil, submitted == nil, approver.canApprove(selected) {
                        VStack(spacing: Space.xxs) {
                            SlideToApprove(armed: armed, armDelay: TimeInterval(selected.armDelayMs) / 1000, busy: busy) {
                                approve(selected)
                            }
                            .id(selected.id)
                            Button("Deny selected option") { denying = selected }
                                .buttonStyle(QuietButtonStyle(tint: Ink.secondary))
                                .disabled(busy)
                        }
                        .padding(.horizontal, Space.gutter)
                        .padding(.top, Space.m)
                        .background(Ink.canvas.ignoresSafeArea(edges: .bottom))
                    }
                }
                .task(id: scenePhase == .active ? selected?.id : nil) {
                    await arm(scenePhase == .active ? selected : nil)
                }
        }
        .background(Ink.canvas.ignoresSafeArea())
        .navigationTitle("Review requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $details) { record in
            AllDetails(record: record, macName: approver.mac(record.bogoID)?.name)
        }
        .sheet(item: $denying) { record in
            DenySheet(agent: record.request?.agentName) { note in
                denying = nil
                if case .nothingSigned(let reason) = approver.deny(record, note: note) { problem = reason }
            }
        }
        .alert("Nothing was approved", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private func scroll(_ cards: [RequestRecord], selected: RequestRecord?, winner: RequestRecord?, submitted: RequestRecord?, closed: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(Formatting.visible(group.title)).type(.title).foregroundStyle(Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Title provided by the agent").type(.label).foregroundStyle(Ink.tertiary)
                }
                Hairline()
                ForEach(cards) { record in
                    option(record, checked: record.id == (winner ?? submitted ?? selected)?.id)
                        .disabled(winner != nil || submitted != nil || busy)
                }
                if let winner {
                    Text("This group is closed.").type(.callout).foregroundStyle(Ink.secondary)
                    let status = winner.phase == .settled(nil) ? "Approved on another device" : Formatting.status(winner, now: approver.nowMs)
                    let ink = Formatting.history(winner).mark == .approved || winner.phase == .settled(nil) ? Ink.positive : Ink.secondary
                    Text(status ?? "Approved").type(.headline).foregroundStyle(ink)
                } else if closed {
                    Text("Another option was selected.").type(.callout).foregroundStyle(Ink.secondary)
                } else if submitted != nil {
                    Text("Approval submitted. Waiting for confirmation from BOGO.")
                        .type(.callout).foregroundStyle(Ink.secondary)
                } else if let selected, let request = selected.request {
                    Text("Approving one option withdraws the others.").type(.callout).foregroundStyle(Ink.secondary)
                    Hairline()
                    let review = Review(request)
                    ReviewSummary(review: review, received: selected.receivedMs)
                    ReasonSection(review: review)
                    DetailsSection(review: review, macName: approver.mac(selected.bogoID)?.name, waiting: 1) {
                        details = selected
                    }
                } else if cards.isEmpty {
                    Text(Formatting.status(anchor, now: approver.nowMs) ?? "This group has no options available.")
                        .type(.callout).foregroundStyle(Ink.secondary)
                } else {
                    Text("Select an option to review its details.").type(.callout).foregroundStyle(Ink.secondary)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
        }
    }

    private func option(_ record: RequestRecord, checked: Bool) -> some View {
        Button {
            if selection != record.id {
                armed = false
                selection = record.id
            }
        } label: {
            if let request = record.request {
                let review = Review(request)
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(checked ? Ink.primary : Ink.tertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(Formatting.visible(Formatting.title(review))).type(.headline).foregroundStyle(Ink.primary)
                        if let subtitle = review.subtitle {
                            Text(Formatting.prose(subtitle)).type(.callout).foregroundStyle(Ink.secondary)
                        }
                        Text(Formatting.action(review) + AttributedString(" · ") + Formatting.visible(request.agentName))
                            .type(.label).foregroundStyle(Ink.secondary)
                        if review.subtitle == nil {
                            ForEach(previewRows(review)) { argument in
                                if let value = argument.leaf {
                                    Text(Formatting.visible(argument.label ?? "Argument") + AttributedString(" · ") + Formatting.summary(value))
                                        .type(.callout).foregroundStyle(Ink.secondary).lineLimit(3)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if let price = review.price, case .money(let amount, _) = price.value {
                        Text(amount.formatted).type(.headline).monospacedDigit().foregroundStyle(Ink.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
                .background(Ink.raised, in: RoundedRectangle(cornerRadius: Radius.field))
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private func previewRows(_ review: Review) -> [Review.ArgumentRow] {
        let titlePath = review.highlights.first { $0.role == .title }?.path
        let pricePath = review.price?.path
        return Array((review.arguments ?? []).filter { row in
            guard row.depth == 0, row.leaf != nil else { return false }
            return ![titlePath, pricePath].contains { path in
                guard case .key(let key)? = path?.first, path?.count == 1 else { return false }
                return key == row.label
            }
        }.prefix(3))
    }

    private func arm(_ record: RequestRecord?) async {
        armed = false
        guard let record else { return }
        try? await Task.sleep(for: .seconds(TimeInterval(record.armDelayMs) / 1000))
        if !Task.isCancelled, scenePhase == .active, selection == record.id { armed = true }
    }

    private func approve(_ record: RequestRecord) {
        busy = true
        Task {
            let result = await approver.approve(record)
            busy = false
            switch result {
            case .decided: Haptics.soft()
            case .nothingSigned(let reason): problem = reason
            }
        }
    }
}

struct ApprovedSummary: Equatable {
    let title: String
    let price: MoneyAmount?
    let mac: String
}


struct ReviewSummary: View {
    let review: Review
    let received: UInt64

    var body: some View {
        let request = review.request
        VStack(alignment: .leading, spacing: 0) {
            Text(Formatting.visible(Formatting.title(review)))
                .type(.title)
                .foregroundStyle(Ink.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = review.subtitle, review.price == nil {
                Text(Formatting.visible(subtitle))
                    .type(.body)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(2)
                    .padding(.top, Space.xxs)
            }
            Text(Formatting.visible(request.agentName) + AttributedString(" · " + Formatting.when(Date(timeIntervalSince1970: TimeInterval(received) / 1000))))
                .type(.callout)
                .foregroundStyle(Ink.secondary)
                .lineLimit(2)
                .padding(.top, Space.xs)
                .accessibilityLabel(Text("From \(request.agentName), \(Formatting.when(Date(timeIntervalSince1970: TimeInterval(received) / 1000)))"))
            if let image = review.image {
                HeroPicture(link: image)
                    .padding(.top, Space.xl)
                if review.pictures.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: Space.xs) {
                            ForEach(review.pictures.filter { $0 != image }, id: \.self) { PictureThumb(link: $0, size: 52) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.top, Space.s)
                    .accessibilityLabel("\(review.pictures.count - 1) more pictures from the agent")
                }
            }
            if let price = review.price {
                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle = review.subtitle {
                        Text(Formatting.visible(subtitle)).type(.body).foregroundStyle(Ink.secondary).lineLimit(2)
                    }
                    PriceView(highlight: price)
                }
                .padding(.top, Space.xl)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PriceView: View {
    let highlight: Review.Highlight

    var body: some View {
        switch highlight.value {
        case .money(let amount, _):
            Text(amount.formatted)
                .type(.display)
                .foregroundStyle(Ink.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityLabel(amount.formatted)
        case .unformattable(let value, let currency):
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(Formatting.value(value)).type(.title2).monospaced()
                Text("\(Formatting.visible(highlight.label)) can’t be shown as \(currency)")
                    .type(.label)
                    .foregroundStyle(Ink.warning)
            }
        case .text, .missing:
            EmptyView()
        }
    }
}

struct ReasonSection: View {
    let review: Review

    var body: some View {
        let request = review.request
        VStack(alignment: .leading, spacing: Space.xs) {
            FieldLabel("Reason")
            Group {
                if let justification = request.justification, !justification.isEmpty {
                    Text(Formatting.visible(justification))
                        .type(.body)
                        .foregroundStyle(Ink.primary)
                        .textSelection(.enabled)
                } else {
                    Text(request.justification == nil ? "No reason given" : "Empty reason")
                        .type(.body)
                        .foregroundStyle(Ink.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ForEach(review.warnings, id: \.self) { warning in
                Text(warning)
                    .type(.callout, weight: .medium)
                    .foregroundStyle(Ink.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Warning: \(warning)")
            }
            ForEach(review.reasonPictures, id: \.self) { link in
                HeroPicture(link: link).padding(.vertical, Space.xs)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Not verified by BOGO")
                Text(clientLine(request))
            }
            .type(.caption)
            .foregroundStyle(Ink.tertiary)
            .padding(.top, Space.xxs)
        }
        .accessibilityElement(children: .contain)
    }

    private func clientLine(_ request: ApprovalRequest) -> AttributedString {
        let client = request.clientName.map { Formatting.visible($0) } ?? AttributedString("client not reported")
        return AttributedString("Sent by ") + client + AttributedString(" · session \(request.sessionTag)")
    }
}

struct DetailsSection: View {
    let review: Review
    let macName: String?
    let waiting: Int
    let showDetails: () -> Void

    var body: some View {
        let request = review.request
        let details = review.details
        let names = Formatting.fieldNames(details + review.missing)
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Details").padding(.bottom, Space.xxs)
            DetailRow(Text("Action")) { Text(Formatting.action(review)) }
            ForEach(details) { highlight in
                if case .text(let value) = highlight.value {
                    DetailRow(Text(Formatting.visible(names[highlight.id] ?? highlight.label))) {
                        Text(Formatting.summary(value)).lineLimit(6)
                    }
                }
            }
            if let expires = request.expires {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    DetailRow(Text("Expires in")) {
                        Text(context.date < expires ? Formatting.remaining(expires, now: context.date) : "Expired")
                            .monospacedDigit()
                            .foregroundStyle(context.date < expires ? Ink.primary : Ink.negative)
                    }
                }
            }
            DetailRow(Text("Requested by")) { Text(Formatting.visible(request.agentName)) }
            DetailRow(Text("Runs on")) { Text(Formatting.visible(macName ?? "Unknown Mac")) }
            if review.image != nil {
                DetailRow(Text("Image")) { Text("From the agent") }
            }
            if !review.missing.isEmpty {
                Text(Formatting.visible("Not in this request: " + review.missing.map { names[$0.id] ?? $0.label }.joined(separator: ", ")))
                    .type(.caption)
                    .foregroundStyle(Ink.secondary)
                    .padding(.vertical, Space.xs)
            }
            if waiting > 1 {
                Text("\(waiting) identical requests are waiting. Approve or Deny decides this one, the oldest.")
                    .type(.caption)
                    .foregroundStyle(Ink.secondary)
                    .padding(.vertical, Space.xs)
            }
            Hairline().padding(.top, Space.s)
            AllDetailsRow(count: review.request.arguments.map(ArgumentCount.leaves) ?? 0, action: showDetails)
        }
    }
}

struct AllDetailsRow: View {
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Text("All details").type(.callout, weight: .semibold).foregroundStyle(Ink.primary)
                Spacer()
                if let count {
                    Text(count == 1 ? "1 value signed" : "\(count) values signed").type(.label).foregroundStyle(Ink.tertiary)
                }
                Chevron()
            }
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the full, exact request you sign")
    }
}

enum ArgumentCount {
    static func leaves(_ value: ArgumentValue) -> Int {
        switch value {
        case .array(let items): return items.isEmpty ? 1 : items.map(leaves).reduce(0, +)
        case .object(let members): return members.isEmpty ? 1 : members.map { leaves($0.value) }.reduce(0, +)
        default: return 1
        }
    }
}

struct StatusLine: View {
    let text: String
    let mark: Formatting.Mark
    let pending: Bool

    var body: some View {
        Text(text)
            .type(.callout, weight: .semibold)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        if pending { return Ink.secondary }
        switch mark {
        case .approved: return Ink.positive
        case .denied: return Ink.negative
        case .ended, .paused: return Ink.secondary
        }
    }
}

struct UnreadableSection: View {
    let record: RequestRecord
    let macName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("BOGO couldn’t read this request").type(.title).foregroundStyle(Ink.primary).accessibilityAddTraits(.isHeader)
            Text("It can’t show what this would run, so it can’t be approved. You can deny it.")
                .type(.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(macName ?? "Unknown Mac") · \(record.bytes.count) bytes")
                .type(.callout)
                .foregroundStyle(Ink.tertiary)
                .padding(.top, Space.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ApprovedOverlay: View {
    let summary: ApprovedSummary
    let done: () -> Void
    @State private var text = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            VStack(spacing: Space.xl) {
                Spacer()
                DoneMark(size: 88)
                VStack(spacing: Space.xs) {
                    Text("Approved").type(.title).foregroundStyle(Ink.primary)
                    if let price = summary.price {
                        Text(price.formatted).type(.title2).monospacedDigit().foregroundStyle(Ink.primary)
                    }
                    Text(Formatting.visible(summary.title)).type(.body).foregroundStyle(Ink.secondary).multilineTextAlignment(.center).lineLimit(2)
                    Text("Signed with Face ID and sent to \(summary.mac)")
                        .type(.caption)
                        .foregroundStyle(Ink.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Space.s)
                }
                .opacity(text ? 1 : 0)
                .offset(y: text || reduceMotion ? 0 : 8)
                .padding(.horizontal, Space.xxl)
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Space.gutter)
                    .opacity(text ? 1 : 0)
            }
            .padding(.bottom, Space.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Approved")
        .onAppear {
            withAnimation(reduceMotion ? Motion.fade : Motion.standard.delay(0.45)) { text = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            done()
        }
    }
}

struct DenySheet: View {
    let agent: String?
    let deny: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Deny this request?").type(.title2).foregroundStyle(Ink.primary)
                Text("\(agent ?? "The agent") is told you said no. Nothing runs.")
                    .type(.callout)
                    .foregroundStyle(Ink.secondary)
            }
            TextField("Add a note for the agent (optional)", text: $note, axis: .vertical)
                .type(.body)
                .lineLimit(1...3)
                .focused($focused)
                .padding(Space.m)
                .background(Ink.raised, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            VStack(spacing: Space.xxs) {
                Button("Deny request") { deny(note) }
                    .buttonStyle(DestructiveButtonStyle())
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xxl)
        .padding(.bottom, Space.xs)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Ink.canvas.ignoresSafeArea())
        .presentationDetents([.height(380), .large])
        .presentationCornerRadius(Radius.sheet)
        .presentationDragIndicator(.visible)
    }
}
