import BogoCrypto
import BogoModel
import CryptoKit
import Foundation

enum RegWire {
    static let hello: UInt8 = 0x01
    static let commit: UInt8 = 0x02
    static let phoneNonce: UInt8 = 0x03
    static let reveal: UInt8 = 0x04
    static let macConfirmed: UInt8 = 0x05
    static let regSubmit: UInt8 = 0x06
    static let registered: UInt8 = 0x07
    static let refused: UInt8 = 0x08
    static let macAbort: UInt8 = 0x09
    static let phoneAbort: UInt8 = 0x0a
    static let macOffer: UInt8 = 0x0b

    static func sha(_ parts: Data...) -> Data {
        Data(SHA256.hash(data: parts.reduce(Data(), +)))
    }

    static func tag(_ text: String) -> Data { Data(text.utf8) }

    static func msgID(offer: Data, phase: UInt8) -> Data {
        sha(tag("bogo-reg-msg"), offer, Data([phase])).prefix(16)
    }

    static func commitment(ePubM: Data, ePubP: Data, nM: Data) -> Data {
        sha(tag("bogo-reg-commit"), ePubM, ePubP, nM)
    }

    static func transcriptHash(offer: Data, ePubM: Data, ePubP: Data, commit: Data, nM: Data, nP: Data) -> Data {
        sha(tag("bogo-reg-transcript/v1"), offer, ePubM, ePubP, commit, nM, nP)
    }

    static func txID(_ transcriptHash: Data) -> Data { sha(transcriptHash) }

    static func approverID(_ txID: Data) -> Data { sha(tag("bogo-approver-id/v1"), txID) }

    static func phaseKey(shared: Data, transcriptHash: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: shared), salt: transcriptHash, info: tag("bogo-reg-key/v1"), outputByteCount: 32)
    }

    static func nonce(_ phase: UInt8) throws -> ChaChaPoly.Nonce {
        try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 11) + Data([phase]))
    }

    static func aad(offer: Data, phase: UInt8) -> Data {
        tag("bogo-reg/v1") + offer + Data([phase])
    }

    static func seal(_ plaintext: Data, key: SymmetricKey, offer: Data, phase: UInt8) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce(phase), authenticating: aad(offer: offer, phase: phase))
        return box.ciphertext + box.tag
    }

    static func open(_ sealed: Data, key: SymmetricKey, offer: Data, phase: UInt8) -> Data? {
        guard sealed.count >= 16, let box = try? ChaChaPoly.SealedBox(nonce: nonce(phase), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16)) else { return nil }
        return try? ChaChaPoly.open(box, using: key, authenticating: aad(offer: offer, phase: phase))
    }

    static func roomAAD(room: Data, phase: UInt8) -> Data {
        tag("bogo-pair/v1") + room + Data([phase])
    }

    static func sealRoom(_ payload: Data, key: SymmetricKey, room: Data, phase: UInt8) throws -> Data {
        let box = try ChaChaPoly.seal(payload, using: key, nonce: nonce(phase), authenticating: roomAAD(room: room, phase: phase))
        return Data([phase]) + box.ciphertext + box.tag
    }

    static func openRoom(_ body: Data, key: SymmetricKey, room: Data) -> (phase: UInt8, payload: Data)? {
        guard let phase = body.first, body.count >= 17,
              let box = try? ChaChaPoly.SealedBox(nonce: nonce(phase), ciphertext: body.dropFirst().dropLast(16), tag: body.suffix(16)),
              let payload = try? ChaChaPoly.open(box, using: key, authenticating: roomAAD(room: room, phase: phase)) else { return nil }
        return (phase, payload)
    }

    static func random(_ count: Int) -> Data {
        var bytes = Data(count: count)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return bytes
    }

    static func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

public struct PairCode: Equatable, Sendable {
    public let secret: Data
    public let relay: String?

    static let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789".utf8)

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        let code = parts[0].lowercased()
        guard code.hasPrefix("bogo1-") else { return nil }
        var bits: UInt32 = 0
        var count = 0
        var secret = Data()
        for c in code.dropFirst(6).utf8 where c != UInt8(ascii: "-") && c != UInt8(ascii: " ") {
            guard let value = Self.alphabet.firstIndex(of: c) else { return nil }
            bits = (bits << 5) | UInt32(value)
            count += 5
            if count >= 8 {
                count -= 8
                secret.append(UInt8(truncatingIfNeeded: bits >> UInt32(count)))
            }
        }
        guard secret.count == 15 else { return nil }
        var relay: String?
        if parts.count == 2 {
            var host = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            if host.hasSuffix(":443") { host.removeLast(4) }
            guard !host.isEmpty, host.rangeOfCharacter(from: CharacterSet(charactersIn: "/@?# ")) == nil,
                  URL(string: "https://" + host)?.host() != nil else { return nil }
            relay = host
        }
        self.secret = secret
        self.relay = relay
    }

    var room: Data { RegWire.sha(RegWire.tag("bogo-pair-room/v1"), secret).prefix(16) }

    var roomKey: SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), salt: Data(), info: RegWire.tag("bogo-pair-key/v1"), outputByteCount: 32)
    }

    func endpoint(publicRelay: RelayEndpoint) -> RelayEndpoint {
        relay.flatMap { URL(string: "https://" + $0) }.map(RelayEndpoint.init) ?? publicRelay
    }
}

@MainActor
final class RelayRegistration: RegistrationChannel {
    let code: String? = nil
    private let client: RelayClient
    private let keys: ChannelKeys
    private let room: Room
    private let transcriptHash: Data
    private let key: SymmetricKey
    private var confirmed: (macE2E: Data, macRelay: Data, bogoID: Data)?
    private var challenge: Data?
    private var aborted = false

    static let poll: Duration = .milliseconds(300)

    struct Room {
        let id: Data
        let key: SymmetricKey
    }

    static func begin(client: RelayClient, keys: ChannelKeys, code: PairCode) async throws -> RelayRegistration {
        let room = Room(id: code.room, key: code.roomKey)
        let ePubM = try await wait(client, room, for: [RegWire.macOffer], timeout: .seconds(10), closed: .noMac).payload
        guard ePubM.count == 32 else { throw RegistrationError.tampered }
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ePubP = ephemeral.publicKey.rawRepresentation
        try await send(client, room, RegWire.hello, ePubP)
        let commit = try await wait(client, room, for: [RegWire.commit]).payload
        guard commit.count == 32 else { throw RegistrationError.tampered }
        let nP = RegWire.random(16)
        try await send(client, room, RegWire.phoneNonce, nP)
        let nM = try await wait(client, room, for: [RegWire.reveal]).payload
        guard nM.count == 16, RegWire.commitment(ePubM: ePubM, ePubP: ePubP, nM: nM) == commit else {
            try? await send(client, room, RegWire.phoneAbort, Data())
            throw RegistrationError.tampered
        }
        let macKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ePubM)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: macKey).withUnsafeBytes { Data($0) }
        guard shared.contains(where: { $0 != 0 }) else {
            try? await send(client, room, RegWire.phoneAbort, Data())
            throw RegistrationError.tampered
        }
        let th = RegWire.transcriptHash(offer: room.id, ePubM: ePubM, ePubP: ePubP, commit: commit, nM: nM, nP: nP)
        return RelayRegistration(client: client, keys: keys, room: room, transcriptHash: th,
                                 key: RegWire.phaseKey(shared: shared, transcriptHash: th))
    }

    private init(client: RelayClient, keys: ChannelKeys, room: Room, transcriptHash: Data, key: SymmetricKey) {
        self.client = client
        self.keys = keys
        self.room = room
        self.transcriptHash = transcriptHash
        self.key = key
    }

    var txID: Data { RegWire.txID(transcriptHash) }

    func macConfirmation() async throws -> MacConfirmation {
        let sealed = try await Self.wait(client, room, for: [RegWire.macConfirmed], until: { [weak self] in self?.aborted ?? true }).payload
        guard let plain = RegWire.open(sealed, key: key, offer: room.id, phase: RegWire.macConfirmed), let fields = RegWire.json(plain),
              let macE2E = (fields["macE2e"] as? String).flatMap(Hex.data), macE2E.count == 32,
              let macRelay = (fields["macRelay"] as? String).flatMap(Hex.data), macRelay.count == 32,
              let bogoID = (fields["bogoId"] as? String).flatMap(Hex.data), bogoID == RegWire.sha(macE2E),
              let challenge = (fields["challenge"] as? String).flatMap(Hex.data), challenge.count == 32,
              let name = fields["macName"] as? String, !name.isEmpty else {
            abort()
            throw RegistrationError.tampered
        }
        confirmed = (macE2E, macRelay, bogoID)
        self.challenge = challenge
        return MacConfirmation(bogoID: bogoID, macName: name, challenge: challenge, transcriptHash: transcriptHash)
    }

    func clientDataHash(approvalKey: Data) -> Data {
        guard let challenge else { return Data() }
        return RegWire.sha(transcriptHash, challenge, approvalKey, keys.e2e.publicKey.rawRepresentation, keys.relay.publicKey.rawRepresentation)
    }

    func saveRoute() throws -> (route: MacRoute, approverID: Data)? {
        guard let confirmed else { throw RegistrationError.macCancelled }
        let account = Hex.string(confirmed.bogoID) + "." + Hex.string(txID.prefix(8))
        try keys.save(account: account)
        let route = MacRoute(macE2E: confirmed.macE2E, macMailbox: RelayClient.mailbox(confirmed.macRelay), txID: txID, channelAccount: account,
                             relayURL: client.endpoint.url)
        return (route, RegWire.approverID(txID))
    }

    func submit(_ submission: RegistrationSubmission) async throws -> Registered {
        let fields: [String: Any] = [
            "approvalKey": Hex.string(submission.approvalPublicKey),
            "proof": Hex.string(submission.proof),
            "phoneE2e": Hex.string(keys.e2e.publicKey.rawRepresentation),
            "phoneRelay": Hex.string(keys.relay.publicKey.rawRepresentation),
            "attestation": submission.attestation.map { ["keyId": $0.keyID, "object": $0.object.base64EncodedString()] } ?? NSNull(),
            "pushToken": submission.pushToken.map(Hex.string) ?? NSNull(),
            "pushEnv": submission.pushToken == nil ? NSNull() : submission.pushEnvironment as Any,
            "encodingVersions": [1],
        ]
        let plain = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        let sealed = try RegWire.seal(plain, key: key, offer: room.id, phase: RegWire.regSubmit)
        do {
            try await Self.send(client, room, RegWire.regSubmit, sealed)
            let answer = try await Self.wait(client, room, for: [RegWire.registered, RegWire.refused], timeout: .seconds(90), closed: .unanswered)
            if answer.phase == RegWire.refused {
                let why = RegWire.open(answer.payload, key: key, offer: room.id, phase: RegWire.refused).flatMap(RegWire.json)?["why"] as? String
                throw RegistrationError.refused(why ?? "")
            }
            guard let opened = RegWire.open(answer.payload, key: key, offer: room.id, phase: RegWire.registered), let reply = RegWire.json(opened),
                  let tx = (reply["txId"] as? String).flatMap(Hex.data), let approver = (reply["approverId"] as? String).flatMap(Hex.data),
                  tx == txID, approver == RegWire.approverID(txID) else { throw RegistrationError.unanswered }
            return Registered(txID: tx, approverID: approver)
        } catch RegistrationError.refused(let why) {
            throw RegistrationError.refused(why)
        } catch RegistrationError.macCancelled {
            throw RegistrationError.macCancelled
        } catch {
            throw RegistrationError.unanswered
        }
    }

    func abort() {
        guard !aborted else { return }
        aborted = true
        let (client, room) = (client, room)
        Task { try? await Self.send(client, room, RegWire.phoneAbort, Data()) }
    }

    private static func send(_ client: RelayClient, _ room: Room, _ phase: UInt8, _ payload: Data) async throws {
        try await client.roomSend(room.id, msgID: RegWire.msgID(offer: room.id, phase: phase),
                                  body: RegWire.sealRoom(payload, key: room.key, room: room.id, phase: phase))
    }

    private static func wait(_ client: RelayClient, _ room: Room, for phases: Set<UInt8>, timeout: Duration = .seconds(600),
                             closed: RegistrationError = .macCancelled,
                             until cancelled: @MainActor () -> Bool = { false }) async throws -> (phase: UInt8, payload: Data) {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if cancelled() || Task.isCancelled { throw RegistrationError.macCancelled }
            let messages: [RelayMessage]
            do {
                messages = try await client.roomFetch(room.id)
            } catch RelayError.status(404), RelayError.status(403) {
                throw closed
            } catch {
                try await Task.sleep(for: .seconds(1))
                continue
            }
            for message in messages {
                guard let (phase, payload) = RegWire.openRoom(message.body, key: room.key, room: room.id),
                      message.msgID == Hex.string(RegWire.msgID(offer: room.id, phase: phase)) else { continue }
                if phase == RegWire.macAbort { throw RegistrationError.macCancelled }
                if phases.contains(phase) { return (phase, payload) }
            }
            try await Task.sleep(for: poll)
        }
        throw closed == .noMac ? .noMac : RegistrationError.unanswered
    }
}
