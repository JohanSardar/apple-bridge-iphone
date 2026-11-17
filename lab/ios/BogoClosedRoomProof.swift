import BogoCrypto
import BogoModel
import CryptoKit
import Foundation
import ObjectiveC

final class RoomFixture: @unchecked Sendable {
    let lock = NSLock()
    let code = PairCode("bogo1-aaaa-bbbb-cccc-dddd-eeee-ffff")!
    var offer: Data { code.room }
    let mac = Curve25519.KeyAgreement.PrivateKey()
    let nM = Data(repeating: 2, count: 16)
    var ePubP = Data()
    var nP = Data()
    var submitted = false

    func reply(_ request: URLRequest) throws -> (Int, Any) {
        lock.lock()
        defer { lock.unlock() }
        let path = request.url!.path
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let fields = RegWire.json(body) ?? [:]
        if path == "/v1/auth/challenge" {
            return (200, ["challenge": Hex.string(Data(repeating: 3, count: 32))])
        }
        if path == "/v1/auth/verify" { return (200, ["token": "test"]) }
        if path == "/v1/room/send" {
            let (phase, payload) = RegWire.openRoom(Hex.data(fields["body"] as! String)!, key: code.roomKey, room: offer)!
            switch phase {
            case RegWire.hello: ePubP = payload
            case RegWire.phoneNonce: nP = payload
            case RegWire.regSubmit: submitted = true
            default: break
            }
            return (200, [:])
        }
        if path == "/v1/room/fetch" {
            if submitted { return (404, [:]) }
            let ePubM = mac.publicKey.rawRepresentation
            var phases: [(UInt8, Data)] = [(RegWire.macOffer, ePubM)]
            let commit = RegWire.commitment(ePubM: ePubM, ePubP: ePubP, nM: nM)
            if !ePubP.isEmpty { phases.append((RegWire.commit, commit)) }
            if !nP.isEmpty {
                let th = RegWire.transcriptHash(
                    offer: offer, ePubM: ePubM, ePubP: ePubP,
                    commit: commit, nM: nM, nP: nP
                )
                let shared = try mac.sharedSecretFromKeyAgreement(
                    with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: ePubP)
                ).withUnsafeBytes { Data($0) }
                let plain = try JSONSerialization.data(withJSONObject: [
                    "macE2e": Hex.string(ePubM),
                    "macRelay": Hex.string(Data(repeating: 4, count: 32)),
                    "bogoId": Hex.string(RegWire.sha(ePubM)),
                    "macName": "Mac",
                    "challenge": Hex.string(Data(repeating: 5, count: 32))
                ])
                let sealed = try RegWire.seal(
                    plain,
                    key: RegWire.phaseKey(shared: shared, transcriptHash: th),
                    offer: offer,
                    phase: RegWire.macConfirmed
                )
                phases += [(RegWire.reveal, nM), (RegWire.macConfirmed, sealed)]
            }
            return (200, try phases.map { phase, payload in
                [
                    "msg_id": Hex.string(RegWire.msgID(offer: offer, phase: phase)),
                    "from": "mac",
                    "body": Hex.string(try RegWire.sealRoom(payload, key: code.roomKey, room: offer, phase: phase))
                ]
            })
        }
        fatalError("unexpected request: \(path)")
    }
}

final class RoomProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = RoomFixture()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "proof.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (status, object) = try Self.fixture.reply(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self, didLoad: try JSONSerialization.data(withJSONObject: object)
            )
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSessionConfiguration {
    @objc class func proofEphemeral() -> URLSessionConfiguration {
        let config = proofEphemeral()
        config.protocolClasses = [RoomProtocol.self]
        return config
    }
}

@main
enum ClosedRoomProof {
    @MainActor
    static func main() async throws {
        let original = class_getClassMethod(
            URLSessionConfiguration.self,
            #selector(getter: URLSessionConfiguration.ephemeral)
        )!
        let replacement = class_getClassMethod(
            URLSessionConfiguration.self,
            #selector(URLSessionConfiguration.proofEphemeral)
        )!
        method_exchangeImplementations(original, replacement)
        defer { method_exchangeImplementations(original, replacement) }

        let fixture = RoomProtocol.fixture
        let keys = ChannelKeys()
        let client = RelayClient(
            endpoint: RelayEndpoint(url: URL(string: "https://proof.invalid")!),
            key: keys.relay
        )
        let channel = try await RelayRegistration.begin(
            client: client, keys: keys, code: fixture.code
        )
        _ = try await channel.macConfirmation()
        do {
            _ = try await channel.submit(RegistrationSubmission(
                approvalPublicKey: Data(), proof: Data(), attestation: nil,
                pushToken: nil, pushEnvironment: "development"
            ))
            fatalError("expected unanswered")
        } catch RegistrationError.unanswered {
            print("PASS")
        } catch {
            print("FAIL S1: room closed after REG_SUBMIT; expected unanswered to preserve recovery, got \(error)")
            exit(1)
        }
    }
}
