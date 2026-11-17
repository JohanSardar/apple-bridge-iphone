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
                ContentUnavailableView("Request Not Found", systemImage: "questionmark.circle")
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
            VStack(spacing: Space.m) {
                if let status = Formatting.status(record, now: now), !record.phase.isPending || !open, approved == nil {
                    StatusBanner(text: status, mark: Formatting.history(record).mark, pending: record.phase.isPending)
                }
                if let request = record.request {
                    let review = Review(request)
                    ReviewCard(review: review, received: record.receivedMs)
                        .offset(y: arrived ? 0 : 24)
                        .opacity(arrived ? 1 : 0)
                    ReasonCard(review: review)
                        .offset(y: arrived ? 0 : 36)
                        .opacity(arrived ? 1 : 0)
                    DetailsCard(review: review, macName: approver.mac(record.bogoID)?.name,
                                waiting: open ? (entry?.count ?? 1) : 1, showDetails: { details = true })
                        .offset(y: arrived ? 0 : 48)
                        .opacity(arrived ? 1 : 0)
                } else {
                    UnreadableCard(record: record, macName: approver.mac(record.bogoID)?.name, showDetails: { details = true })
                }
                Color.clear.frame(height: Space.xs)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.xs)
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
                        Button("Pause \(request.agentName)", systemImage: "pause.circle", role: .destructive) { pausing = true }
                        Button("All details", systemImage: "doc.text.magnifyingglass") { details = true }
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
        .padding(.bottom, Space.xxs)
        .background {
            LinearGradient(stops: [.init(color: Ink.canvas.opacity(0), location: 0), .init(color: Ink.canvas, location: 0.28)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
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
                    approved = ApprovedSummary(title: review?.title ?? "Request",
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

struct ApprovedSummary: Equatable {
    let title: String
    let price: MoneyAmount?
    let mac: String
}

struct ReviewCard: View {
    let review: Review
    let received: UInt64

    var body: some View {
        let request = review.request
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.xs) {
                Monogram(request.agentName)
                Text(Formatting.visible(request.agentName)).type(.label, weight: .semibold).foregroundStyle(Ink.primary).lineLimit(1)
                Text(asks).type(.label).foregroundStyle(Ink.secondary).lineLimit(1)
                Spacer(minLength: Space.xs)
                Text(Formatting.when(Date(timeIntervalSince1970: TimeInterval(received) / 1000)))
                    .type(.caption)
                    .foregroundStyle(Ink.tertiary)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Formatting.visible(review.title))
                    .type(.title)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = review.subtitle, compact {
                    Text(Formatting.visible(subtitle)).type(.body, weight: .medium).foregroundStyle(Ink.secondary).lineLimit(2)
                }
                Text(Formatting.via(review))
                    .type(.label)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(2)
            }
            if let image = review.image {
                HeroPicture(link: image)
                if review.pictures.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: Space.xs) {
                            ForEach(review.pictures.filter { $0 != image }, id: \.self) { PictureThumb(link: $0, size: 56) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityLabel("\(review.pictures.count - 1) more pictures from the agent")
                }
            }
            if (review.subtitle != nil && !compact) || review.price != nil {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    if let subtitle = review.subtitle, !compact {
                        Text(Formatting.visible(subtitle)).type(.body, weight: .medium).foregroundStyle(Ink.secondary).lineLimit(2)
                    }
                    if let price = review.price { PriceView(highlight: price) }
                }
            }
        }
        .card()
    }

    private var compact: Bool {
        review.image == nil && review.price == nil
    }

    private var asks: String {
        if review.price != nil { return "wants to pay" }
        return "wants to run"
    }
}

struct PriceView: View {
    let highlight: Review.Highlight

    var body: some View {
        switch highlight.value {
        case .money(let amount, _):
            let parts = PriceView.split(amount)
            (Text(parts.main) + Text(parts.minor).foregroundColor(Ink.secondary).font(.system(size: 30, weight: .semibold)))
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
                    .foregroundStyle(Ink.claim)
            }
        case .text, .missing:
            EmptyView()
        }
    }

    static func split(_ amount: MoneyAmount) -> (main: String, minor: String) {
        let text = amount.formatted
        guard amount.exponent > 0, let dot = text.lastIndex(of: ".") else { return (text, "") }
        return (String(text[..<dot]), String(text[dot...]))
    }
}

struct ReasonCard: View {
    let review: Review

    var body: some View {
        let request = review.request
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 11, weight: .bold))
                Text("Agent’s reason").type(.eyebrow)
                Text("· unverified").type(.eyebrow).opacity(0.7)
            }
            .foregroundStyle(Ink.claim)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Agent’s reason, unverified")
            Group {
                if let justification = request.justification, !justification.isEmpty {
                    Text(Formatting.visible(justification, quoted: true))
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
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warning).fixedSize(horizontal: false, vertical: true)
                }
                .type(.callout, weight: .semibold)
                .foregroundStyle(Ink.claim)
                .padding(Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Warning: \(warning)")
            }
            ForEach(review.reasonPictures, id: \.self) { link in
                HeroPicture(link: link)
            }
            Text(clientLine(request))
                .type(.caption)
                .foregroundStyle(Ink.secondary)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.claimWash, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.claim.opacity(0.14), lineWidth: 0.75))
    }

    private func clientLine(_ request: ApprovalRequest) -> AttributedString {
        let client = request.clientName.map { Formatting.visible($0) } ?? AttributedString("client not reported")
        return AttributedString("Sent by ") + client + AttributedString(" · session \(request.sessionTag)")
    }
}

struct DetailsCard: View {
    let review: Review
    let macName: String?
    let waiting: Int
    let showDetails: () -> Void

    var body: some View {
        let request = review.request
        let details = review.details
        let names = Formatting.fieldNames(details + review.missing)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(details) { highlight in
                if case .text(let value) = highlight.value {
                    DetailRow(Text(Formatting.visible(names[highlight.id] ?? highlight.label))) {
                        Text(Formatting.summary(value)).lineLimit(6)
                    }
                    Hairline()
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
                Hairline()
            }
            DetailRow(Text("Requested by")) { Text(Formatting.visible(request.agentName)) }
            Hairline()
            DetailRow(Text("Runs on")) { Text(Formatting.visible(macName ?? "Unknown Mac")) }
            if !review.missing.isEmpty {
                Hairline()
                Text(Formatting.visible("Not in this request: " + review.missing.map { names[$0.id] ?? $0.label }.joined(separator: ", ")))
                    .type(.caption)
                    .foregroundStyle(Ink.secondary)
                    .padding(.vertical, Space.s)
            }
            if waiting > 1 {
                Hairline()
                Text("\(waiting) identical requests are waiting. Approve or Deny decides this one, the oldest.")
                    .type(.caption)
                    .foregroundStyle(Ink.secondary)
                    .padding(.vertical, Space.s)
            }
            Hairline()
            AllDetailsRow(count: review.request.arguments.map(ArgumentCount.leaves) ?? 0, action: showDetails)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.xxs)
        .card(padding: 0)
    }
}

struct AllDetailsRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.accent)
                Text("All details").type(.callout, weight: .semibold).foregroundStyle(Ink.accent)
                Spacer()
                Text(count == 1 ? "1 value signed" : "\(count) values signed").type(.caption).foregroundStyle(Ink.tertiary)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.tertiary)
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

struct StatusBanner: View {
    let text: String
    let mark: Formatting.Mark
    let pending: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
            Text(text).type(.callout, weight: .medium).foregroundStyle(Ink.primary)
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .background(wash, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if pending { return "clock.badge.xmark" }
        switch mark {
        case .approved: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .ended: return "clock.badge.xmark"
        case .paused: return "pause.circle.fill"
        }
    }

    private var tint: Color {
        if pending { return Ink.secondary }
        switch mark {
        case .approved: return Ink.positive
        case .denied: return Ink.negative
        case .ended, .paused: return Ink.secondary
        }
    }

    private var wash: Color {
        if pending { return Ink.raised }
        switch mark {
        case .approved: return Ink.positiveWash
        case .denied: return Ink.negativeWash
        case .ended, .paused: return Ink.raised
        }
    }
}

struct UnreadableCard: View {
    let record: RequestRecord
    let macName: String?
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Tile(symbol: "exclamationmark.triangle.fill", size: 48, tint: Ink.claim, wash: Ink.claimWash)
            Text("BOGO couldn’t read this request").type(.title2).foregroundStyle(Ink.primary)
            Text("It can’t show what this would run, so it can’t be approved. You can deny it.")
                .type(.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(macName ?? "Unknown Mac") · \(record.bytes.count) bytes")
                .type(.caption)
                .foregroundStyle(Ink.tertiary)
        }
        .card(padding: Space.xl)
    }
}

struct ApprovedOverlay: View {
    let summary: ApprovedSummary
    let done: () -> Void
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0
    @State private var text = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            VStack(spacing: Space.xl) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Ink.positiveWash)
                        .scaleEffect(ring)
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(Ink.positive, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    CheckShape()
                        .trim(from: 0, to: check)
                        .stroke(Ink.positive, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .frame(width: 46, height: 36)
                }
                .frame(width: 112, height: 112)
                VStack(spacing: Space.xs) {
                    Text("Approved").type(.title).foregroundStyle(Ink.primary)
                    if let price = summary.price {
                        Text(price.formatted).type(.title).monospacedDigit().foregroundStyle(Ink.primary)
                    }
                    Text(Formatting.visible(summary.title)).type(.body).foregroundStyle(Ink.secondary).multilineTextAlignment(.center).lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: "faceid")
                        Text("Signed with Face ID · sent to \(summary.mac)")
                    }
                    .type(.caption)
                    .foregroundStyle(Ink.tertiary)
                    .padding(.top, Space.xs)
                }
                .opacity(text ? 1 : 0)
                .offset(y: text ? 0 : 10)
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
            if reduceMotion {
                ring = 1
                check = 1
                withAnimation(Motion.fade) { text = true }
            } else {
                withAnimation(.easeOut(duration: 0.45)) { ring = 1 }
                withAnimation(.easeOut(duration: 0.35).delay(0.32)) { check = 1 }
                withAnimation(Motion.standard.delay(0.5)) { text = true }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            done()
        }
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
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
                .background(Ink.well, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
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
        .background(Ink.surface.ignoresSafeArea())
        .presentationDetents([.height(380), .large])
        .presentationCornerRadius(Radius.card + 8)
        .presentationDragIndicator(.visible)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.headline)
            .foregroundStyle(Ink.negative)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Ink.negativeWash, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}
