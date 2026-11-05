import CryptoKit
import Foundation

struct CommandPacket: Decodable {
    let ephemeral_key: Data
    let box: Data
    let signature: Data

    func open(gatewayKey: Data, encryption: Data, deviceID: String) throws -> Data {
        let message = Data("apple-bridge-iphone-command/1\0".utf8) + ephemeral_key + box
        guard try Curve25519.Signing.PublicKey(rawRepresentation: gatewayKey).isValidSignature(signature, for: message) else { throw IdentityError.requestFailed }
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: encryption)
        let secret = try key.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral_key))
        let symmetric = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("apple-bridge-iphone/1".utf8), sharedInfo: Data(deviceID.utf8), outputByteCount: 32)
        return try AES.GCM.open(AES.GCM.SealedBox(combined: box), using: symmetric)
    }
}
