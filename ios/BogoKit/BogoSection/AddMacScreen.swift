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
        .presentationCornerRadius(Radius.sheet)
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
                Text("bogo approver add")
                    .type(.mono)
                    .foregroundStyle(Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.m)
                    .background(Ink.raised, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Command: bogo approver add")
                if offers.isEmpty {
                    Searching()
                } else {
                    RowSection("Ready to add") {
                        ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
                            if index > 0 { Hairline() }
                            Button { start(offer) } label: {
                                HStack(spacing: Space.s) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(offer.label).type(.headline).foregroundStyle(Ink.primary)
                                        Text("Waiting for this iPhone").type(.label).foregroundStyle(Ink.secondary)
                                    }
                                    Spacer()
                                    Chevron()
                                }
                                .padding(.vertical, Space.m)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(offer.label), ready to add")
                        }
                    }
                    .transition(.opacity)
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
                    Text(confirmation?.macName ?? offerName)
                        .type(.callout)
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
                            if busy { ProgressView().tint(Ink.inverse) }
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

/// The 6-digit pairing code in large tabular figures, split 3 + 3.
struct CodeTiles: View {
    let code: String

    var body: some View {
        Text(code.count == 6 ? String(code.prefix(3)) + "\u{2009}\u{2009}" + String(code.suffix(3)) : code)
            .font(.system(size: 48, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Ink.primary)
            .accessibilityLabel(code.map(String.init).joined(separator: " "))
    }
}

struct Searching: View {
    var body: some View {
        HStack(spacing: Space.s) {
            ProgressView()
            Text("Looking for your Mac…").type(.callout).foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
