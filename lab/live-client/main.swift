import CryptoKit
import Foundation

enum IdentityError: Error {
    case keychain(OSStatus), invalidCode, requestFailed
}

struct DeviceIdentity: Codable {
    let signing: Data
    let encryption: Data
    var deviceID: String?
    var address: String?
    var fingerprint: String?
    var remote: Bool?
    var gatewayKey: Data?
    var pushToken: String?

    static var path: String { ProcessInfo.processInfo.environment["LIVE_CLIENT_IDENTITY"] ?? "" }

    static func load() throws -> DeviceIdentity {
        if let data = FileManager.default.contents(atPath: path) { return try JSONDecoder().decode(DeviceIdentity.self, from: data) }
        return DeviceIdentity(signing: Curve25519.Signing.PrivateKey().rawRepresentation, encryption: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
    }

    func save() throws {
        try JSONEncoder().encode(self).write(to: URL(fileURLWithPath: Self.path), options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.path)
    }
}

struct CommandPacket: Decodable {
    let ephemeral_key: Data
    let box: Data
    let signature: Data
}

struct PhoneResult: Codable {
    let command_id: String
    let request_hash: String
    let state: String
    let data: JSONValue
}

func open(_ packet: CommandPacket, identity: DeviceIdentity) throws -> PhoneJob {
    guard let gateway = identity.gatewayKey, let id = identity.deviceID else { throw IdentityError.invalidCode }
    let message = Data("apple-bridge-iphone-command/1\0".utf8) + packet.ephemeral_key + packet.box
    guard try Curve25519.Signing.PublicKey(rawRepresentation: gateway).isValidSignature(packet.signature, for: message) else { throw IdentityError.requestFailed }
    let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: identity.encryption)
    let secret = try key.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: packet.ephemeral_key))
    let symmetric = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("apple-bridge-iphone/1".utf8), sharedInfo: Data(id.utf8), outputByteCount: 32)
    let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: packet.box), using: symmetric)
    return try JSONDecoder().decode(PhoneJob.self, from: plain)
}

func drain() async throws -> [String] {
    let identity = try DeviceIdentity.load()
    let raw = try await PairingClient.signedRequest(identity: identity, path: "/v1/iphone/pending")
    var answered: [String] = []
    for packet in try JSONDecoder().decode([CommandPacket].self, from: raw) {
        let job = try open(packet, identity: identity)
        guard job.expires > Int64(Date().timeIntervalSince1970), case .string(let target) = job.command.args["device_id"], target == identity.deviceID else { continue }
        let ping = job.command.op == "iphone.ping"
        let result = PhoneResult(command_id: job.command.command_id, request_hash: job.request_hash, state: ping ? "observed" : "rejected", data: ping ? .object(["pong": .bool(true)]) : .null)
        _ = try await PairingClient.signedRequest(identity: identity, path: "/v1/iphone/result", payload: JSONEncoder().encode(result))
        answered.append(job.command.op)
    }
    return answered
}

@main
struct LiveClient {
    static func main() async throws {
        let arguments = CommandLine.arguments
        switch arguments.dropFirst().first {
        case "pair":
            let identity = try await PairingClient.pair(arguments[2])
            print("paired", identity.deviceID ?? "", "gateway_key", identity.gatewayKey != nil, "remote", identity.remote ?? false)
        case "status":
            let data = try await PairingClient.signedRequest(identity: DeviceIdentity.load(), path: "/v1/iphone/status")
            print("status bytes", data.count)
        case "push-token":
            let body = try JSONSerialization.data(withJSONObject: ["token": arguments[2]])
            _ = try await PairingClient.signedRequest(identity: DeviceIdentity.load(), path: "/v1/iphone/push-token", payload: body)
            print("push token registered")
        case "drain":
            print("answered", try await drain())
        default:
            print("usage: live-client pair <code> | status | push-token <hex> | drain")
        }
    }
}
