import BogoCrypto
import Foundation
import ObjectiveC

@main
enum ApprovalKeyFailureProof {
    @MainActor
    static func main() async throws {
        let original = class_getClassMethod(URLSessionConfiguration.self,
            #selector(getter: URLSessionConfiguration.ephemeral))!
        let replacement = class_getClassMethod(URLSessionConfiguration.self,
            #selector(URLSessionConfiguration.proofEphemeral))!
        method_exchangeImplementations(original, replacement)
        defer { method_exchangeImplementations(original, replacement) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let endpoint = RelayEndpoint(url: URL(string: "https://proof.invalid")!)
        let phone = PhoneApprover(directory: directory, link: RelayMacLink(endpoint: endpoint))
        let keys = ChannelKeys()
        let channel = try await RelayRegistration.begin(
            client: RelayClient(endpoint: endpoint, key: keys.relay), keys: keys, code: RoomProtocol.fixture.code)
        let confirmation = try await channel.macConfirmation()
        do {
            _ = try await phone.completeRegistration(channel, confirmation: confirmation)
            fatalError("expected injected Keychain failure")
        } catch KeychainError.status(-34018) {}
        for _ in 0..<1000 {
            if RoomProtocol.fixture.abortReason != nil { break }
            await Task.yield()
        }
        guard RoomProtocol.fixture.abortReason?.contains("-34018") == true else {
            print("FAIL S1: approval-key save failed (-34018), but Mac received no PHONE_ABORT reason")
            exit(1)
        }
        print("PASS S1")
    }
}
