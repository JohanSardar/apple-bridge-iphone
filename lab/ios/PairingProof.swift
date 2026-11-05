import CryptoKit
import Foundation

@main
struct PairingProof {
    static func field(_ fixture: [String: Any], _ name: String) -> String { fixture[name] as? String ?? "" }
    static func bytes(_ fixture: [String: Any], _ name: String) -> Data { Data(base64Encoded: field(fixture, name)) ?? Data() }
    static func hex(_ value: String) -> Data {
        stride(from: 0, to: value.count, by: 2).reduce(into: Data()) { out, offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            out.append(UInt8(value[start..<value.index(start, offsetBy: 2)], radix: 16) ?? 0)
        }
    }
    static func encode(_ value: [String: Any]) throws -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer: UInt64 = 0
        var bits = 0
        var out = "ab1-"
        for byte in try JSONSerialization.data(withJSONObject: value) {
            buffer = (buffer << 8) | UInt64(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[Int((buffer >> UInt64(bits)) & 31)])
            }
            buffer &= (1 << UInt64(bits)) - 1
        }
        if bits > 0 { out.append(alphabet[Int((buffer << UInt64(5 - bits)) & 31)]) }
        return out
    }
    static func accepts(_ code: PairCode, _ result: PairedDevice, signing: Data, encryption: Data) -> Bool {
        (try? PairingClient.verifiedGatewayKey(code: code, result: result, signing: signing, encryption: encryption)) != nil
    }

    static func main() throws {
        let directory = CommandLine.arguments[1]
        let pairing = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: directory + "/iphone-pairing.json"))) as? [String: Any] ?? [:]
        let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: directory + "/iphone.json"))) as? [String: Any] ?? [:]
        var checks: [String: Bool] = [:]

        let signing = bytes(pairing, "signing_key")
        let encryption = bytes(pairing, "encryption_key")
        let gateway = bytes(pairing, "gateway_key")
        let device = field(pairing, "device_id")
        var raw: [String: Any] = ["id": field(pairing, "pairing_id"), "purpose": "iphone", "address": field(pairing, "address"), "fingerprint": String(repeating: "a", count: 64), "gateway_key": field(pairing, "gateway_key"), "secret": field(pairing, "secret"), "expires_at": "2099-01-01T00:00:00Z", "remote": true]
        let code = try PairCode.decode(try encode(raw))
        checks["code_with_key_decodes"] = code.gateway_key == gateway

        var older = raw
        older["gateway_key"] = nil
        checks["remote_code_without_key_is_refused"] = (try? PairCode.decode(try encode(older))) == nil
        older["remote"] = false
        let pinnedCode = try? PairCode.decode(try encode(older))
        checks["pinned_code_without_key_still_decodes"] = pinnedCode != nil
        if let pinnedCode {
            checks["pinned_code_takes_the_key_over_the_pinned_channel"] = accepts(pinnedCode, PairedDevice(id: device, gateway_key: gateway, pair_proof: nil), signing: signing, encryption: encryption)
            checks["pinned_code_refuses_a_missing_key"] = !accepts(pinnedCode, PairedDevice(id: device, gateway_key: nil, pair_proof: nil), signing: signing, encryption: encryption)
        }
        var short = raw
        short["gateway_key"] = Data([1, 2, 3]).base64EncodedString()
        checks["code_with_a_short_key_is_refused"] = (try? PairCode.decode(try encode(short))) == nil
        raw["unknown_future_field"] = "ignored"
        checks["code_tolerates_new_fields"] = (try? PairCode.decode(try encode(raw))) != nil

        let proof = bytes(pairing, "pair_proof")
        let good = PairedDevice(id: device, gateway_key: gateway, pair_proof: proof)
        checks["authentic_response_is_accepted"] = accepts(code, good, signing: signing, encryption: encryption)
        let attacker = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        checks["substituted_key_is_refused"] = !accepts(code, PairedDevice(id: device, gateway_key: attacker, pair_proof: proof), signing: signing, encryption: encryption)
        checks["missing_key_is_refused"] = !accepts(code, PairedDevice(id: device, gateway_key: nil, pair_proof: proof), signing: signing, encryption: encryption)
        checks["missing_proof_is_refused"] = !accepts(code, PairedDevice(id: device, gateway_key: gateway, pair_proof: nil), signing: signing, encryption: encryption)
        checks["altered_proof_is_refused"] = !accepts(code, PairedDevice(id: device, gateway_key: gateway, pair_proof: Data(repeating: 0, count: 32)), signing: signing, encryption: encryption)
        checks["changed_device_is_refused"] = !accepts(code, PairedDevice(id: "iphone:other", gateway_key: gateway, pair_proof: proof), signing: signing, encryption: encryption)
        checks["changed_phone_key_is_refused"] = !accepts(code, good, signing: Data(repeating: 9, count: 32), encryption: encryption)
        var moved = raw
        moved["address"] = "https://other.example.test"
        checks["changed_address_is_refused"] = !accepts(try PairCode.decode(try encode(moved)), good, signing: signing, encryption: encryption)

        checks["remote_phone_without_a_key_must_pair_again"] = !PairingClient.allowsGatewayKeyFetch(remote: true)
        checks["pinned_phone_without_a_key_can_fetch"] = PairingClient.allowsGatewayKeyFetch(remote: false) && PairingClient.allowsGatewayKeyFetch(remote: nil)

        let stored = try JSONSerialization.data(withJSONObject: ["signing": Data(repeating: 1, count: 32).base64EncodedString(), "encryption": Data(repeating: 2, count: 32).base64EncodedString(), "deviceID": "iphone:paired-earlier", "address": "https://mac.example.test", "fingerprint": String(repeating: "a", count: 64), "remote": true, "gatewayKey": field(pairing, "gateway_key"), "pushToken": "00"])
        let restored = try JSONDecoder().decode(DeviceIdentity.self, from: stored)
        checks["identity_saved_by_an_older_app_loads_with_its_key"] = restored.gatewayKey == gateway && restored.deviceID == "iphone:paired-earlier"

        let packetFields = golden["packet"] as? [String: Any] ?? [:]
        let packet = try JSONDecoder().decode(CommandPacket.self, from: JSONSerialization.data(withJSONObject: packetFields))
        let pinned = try Curve25519.Signing.PrivateKey(rawRepresentation: hex(field(golden, "signing_seed_hex"))).publicKey.rawRepresentation
        let recipient = hex(field(golden, "recipient_private_hex"))
        let opened = try? packet.open(gatewayKey: pinned, encryption: recipient, deviceID: field(golden, "info"))
        checks["paired_phone_opens_a_gateway_packet"] = opened.map { String(decoding: $0, as: UTF8.self) } == field(golden, "plaintext")
        checks["paired_phone_refuses_another_signer"] = (try? packet.open(gatewayKey: attacker, encryption: recipient, deviceID: field(golden, "info"))) == nil

        let upload = PairingClient.uploadMessage(path: field(pairing, "upload_path"), deviceID: device, at: Int64(pairing["upload_at"] as? Int ?? 0), length: pairing["upload_length"] as? Int ?? 0, digest: bytes(pairing, "upload_digest"))
        checks["upload_message_matches_the_gateway"] = upload == bytes(pairing, "upload_message")
        checks["live_handle_matches_the_gateway"] = PairingClient.liveHandle(encryptionKey: encryption, task: field(pairing, "live_task")) == field(pairing, "live_handle")

        let failed = checks.filter { !$0.value }.keys.sorted()
        for (name, passed) in checks.sorted(by: { $0.key < $1.key }) { print("\(passed ? "PASS" : "FAIL") \(name)") }
        if !failed.isEmpty { exit(1) }
        print("pairing_proof_pass")
    }
}
