import BogoCrypto
import BogoModel
import BogoRelay
import SwiftUI

struct AddMacScreen: View {
    let approver: PhoneApprover
    @Environment(\.dismiss) private var dismiss
    @State private var offers: [RegistrationOffer] = []
    @State private var looking = true
    @State private var step: Step = .choose
    @State private var offerName = ""

    enum Step {
        case choose
        case compare(RegistrationChannel, MacConfirmation?)
        case confirming(RegistrationChannel, MacConfirmation)
        case added(String)
        case waiting(String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .choose: choose
                case .compare(let channel, let confirmation): compare(channel, confirmation, busy: false)
                case .confirming(let channel, let confirmation): compare(channel, confirmation, busy: true)
                case .added(let name): added(name)
                case .waiting(let name): waiting(name)
                case .failed(let reason): failed(reason)
                }
            }
            .canvas()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .added = step {} else if case .waiting = step {} else {
                        Button("Cancel", systemImage: "xmark", role: .cancel) {
                            if case .compare(let channel, _) = step { channel.abort() }
                            dismiss()
                        }
                    }
                }
            }
        }
        .task { await look() }
        .presentationCornerRadius(Radius.card + 12)
    }

    private var choose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Add a Mac").type(.title).foregroundStyle(Ink.primary)
                    Text("On your Mac, run this command. The Mac shows up here while it waits.")
                        .type(.callout)
                        .foregroundStyle(Ink.secondary)
                }
                HStack(spacing: Space.xs) {
                    Text("$").foregroundStyle(Ink.tertiary)
                    Text("bogo approver add").foregroundStyle(Ink.primary)
                    Spacer()
                }
                .type(.mono)
                .padding(Space.m)
                .background(Ink.well, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Command: bogo approver add")
                if offers.isEmpty {
                    Searching()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.l)
                } else {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("Ready to add")
                        VStack(spacing: 0) {
                            ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
                                if index > 0 { Hairline().padding(.leading, 60) }
                                Button { start(offer) } label: {
                                    HStack(spacing: Space.s) {
                                        Tile(symbol: "laptopcomputer", size: 44)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(offer.label).type(.callout, weight: .semibold).foregroundStyle(Ink.primary)
                                            HStack(spacing: 6) {
                                                StatusDot(Ink.positive)
                                                Text("Waiting for this iPhone").type(.caption).foregroundStyle(Ink.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.tertiary)
                                    }
                                    .padding(.vertical, Space.s)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(offer.label), ready to add")
                            }
                        }
                        .padding(.horizontal, Space.m)
                        .card(padding: 0, radius: Radius.inner + 4)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(Space.gutter)
            .animation(Motion.standard, value: offers.map(\.id))
        }
    }

    private func compare(_ channel: RegistrationChannel, _ confirmation: MacConfirmation?, busy: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Space.xl) {
                VStack(spacing: Space.xs) {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "laptopcomputer")
                        Text(confirmation?.macName ?? offerName)
                    }
                    .type(.label, weight: .semibold)
                    .foregroundStyle(Ink.secondary)
                    Text("Do the codes match?").type(.title).foregroundStyle(Ink.primary)
                }
                CodeTiles(code: channel.code)
                Text(confirmation == nil ? "Check that your Mac shows the same number, then confirm on the Mac." : "Your Mac confirmed. Confirm here to finish.")
                    .type(.callout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, Space.gutter)
            Spacer()
            Spacer()
            Group {
                if let confirmation {
                    Button {
                        confirm(channel, confirmation)
                    } label: {
                        HStack(spacing: Space.xs) {
                            if busy { ProgressView().tint(Ink.inverse) } else { Image(systemName: "faceid") }
                            Text("Confirm with Face ID")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    HStack(spacing: Space.xs) {
                        ProgressView()
                        Text("Waiting for your Mac").type(.callout).foregroundStyle(Ink.secondary)
                    }
                    .frame(height: 56)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.s)
            .animation(Motion.standard, value: confirmation == nil)
        }
        .onChange(of: confirmation == nil) { _, waiting in if !waiting { Haptics.soft() } }
    }

    private func added(_ name: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Space.l) {
                DoneMark()
                Text("\(name) added").type(.title).foregroundStyle(Ink.primary)
                Text("Requests from its agents now come to this iPhone.")
                    .type(.callout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.xxl)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s)
        }
        .onAppear { Haptics.success() }
    }

    private func waiting(_ name: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Space.l) {
                Tile(symbol: "clock", size: 76, tint: Ink.secondary)
                Text("Waiting for \(name)").type(.title).foregroundStyle(Ink.primary).multilineTextAlignment(.center)
                Text("Your Mac hasn’t answered yet. It finishes on its own once the Mac confirms, and shows under Macs until then.")
                    .type(.callout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.xxl)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s)
        }
    }

    private func failed(_ reason: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Space.l) {
                Tile(symbol: "exclamationmark.triangle.fill", size: 76, tint: Ink.claim, wash: Ink.claimWash)
                Text("Mac not added").type(.title).foregroundStyle(Ink.primary)
                Text(reason)
                    .type(.callout)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.xxl)
            Spacer()
            Button("Try again") {
                step = .choose
                Task { await look() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.s)
        }
        .onAppear { Haptics.warning() }
    }

    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }

    private func look() async {
        while case .choose = step, !Task.isCancelled {
            offers = await approver.link.offers(excluding: approver.macs)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func start(_ offer: RegistrationOffer) {
        offerName = offer.label
        Task {
            do {
                let channel = try await approver.beginRegistration(offer)
                step = .compare(channel, nil)
                let confirmation = try await channel.macConfirmation()
                if case .compare = step { step = .compare(channel, confirmation) }
            } catch RegistrationError.tampered {
                step = .failed("The codes couldn’t be checked safely, so nothing was added. Run `bogo approver add` again.")
            } catch {
                switch step {
                case .choose, .compare: step = .failed("The Mac stopped the attempt. Run `bogo approver add` again.")
                default: break
                }
            }
        }
    }

    private func confirm(_ channel: RegistrationChannel, _ confirmation: MacConfirmation) {
        step = .confirming(channel, confirmation)
        Task {
            do {
                let mac = try await approver.completeRegistration(channel, confirmation: confirmation)
                step = .added(mac.name)
            } catch ApprovalKeyError.cancelled {
                step = .compare(channel, confirmation)
            } catch ApprovalKeyError.notRecognized {
                step = .failed("Face ID didn’t match, so no key was created.")
            } catch RegistrationError.unanswered {
                step = .waiting(confirmation.macName)
            } catch RegistrationError.refused(let why) {
                step = .failed(why.isEmpty ? "Your Mac refused this iPhone. Nothing was registered." : "Your Mac refused this iPhone: \(why). Nothing was registered.")
            } catch RegistrationError.macCancelled {
                step = .failed("The Mac stopped the attempt. Nothing was registered.")
            } catch {
                step = .failed("This iPhone couldn’t finish adding the Mac. Nothing was registered.")
            }
        }
    }
}

struct CodeTiles: View {
    let code: String

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(code.enumerated()), id: \.offset) { index, digit in
                if index == 3 { Color.clear.frame(width: Space.xs) }
                Text(String(digit))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Ink.primary)
                    .frame(width: 44, height: 58)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 0.75))
                    .shadow(color: Ink.shadow, radius: 8, y: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(code.map(String.init).joined(separator: " "))
    }
}

struct Searching: View {
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.l) {
            ZStack {
                ForEach(0..<3) { ring in
                    Circle()
                        .stroke(Ink.primary.opacity(0.08), lineWidth: 1)
                        .frame(width: 70 + CGFloat(ring) * 40, height: 70 + CGFloat(ring) * 40)
                }
                Circle()
                    .stroke(Ink.primary.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 70, height: 70)
                    .scaleEffect(sweep ? 2.2 : 1)
                    .opacity(sweep ? 0 : 1)
                Tile(symbol: "laptopcomputer", size: 56)
            }
            .frame(height: 170)
            Text("Looking for your Mac…").type(.callout).foregroundStyle(Ink.secondary)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { sweep = true }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DoneMark: View {
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Ink.positiveWash).scaleEffect(ring)
            Circle().trim(from: 0, to: ring).stroke(Ink.positive, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
            CheckShape().trim(from: 0, to: check)
                .stroke(Ink.positive, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 31)
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                ring = 1
                check = 1
            } else {
                withAnimation(.easeOut(duration: 0.45)) { ring = 1 }
                withAnimation(.easeOut(duration: 0.35).delay(0.32)) { check = 1 }
            }
        }
    }
}
