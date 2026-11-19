import BogoModel
import Foundation

@MainActor
final class GroupedApprovalLink: MacLink {
    var receive: ((Data, Data?, MacMessage) -> Bool)?
    var applied: ((Data, Data) -> Bool)?
    var messages: [PhoneMessage] = []

    func start(macs: [MacRecord]) {}
    func fetch() async {}
    func seal(_ message: PhoneMessage, msgID: Data, for mac: MacRecord) throws -> Data { message.body }
    func send(_ message: PhoneMessage, sealed: Data, msgID: Data, to mac: MacRecord) async throws {
        messages.append(message)
    }
    func offers(excluding macs: [MacRecord]) async -> [RegistrationOffer] { [] }
    func offer(code: String) -> RegistrationOffer? { nil }
    func register(_ offer: RegistrationOffer) async throws -> RegistrationChannel {
        throw URLError(.unsupportedURL)
    }
}

@main
enum BogoGroupedApprovalProof {
    @MainActor
    static func main() async throws {
        let vectors = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("requests.json")
        let data = try Data(contentsOf: vectors)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let fixtures = root["requests"] as! [[String: Any]]
        let requests = ["payment-approved", "payment-with-expiry", "amount-4700.0"].map { name in
            let fixture = fixtures.first { $0["name"] as? String == name }!
            let bytes = Hex.data(fixture["encoded_hex"] as! String)!
            return (bytes, RequestBytes.decode(bytes)!)
        }
        let bogoID = requests[0].1.bogoID
        let ids = requests.map { $0.1.nonce }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(directory: directory)
        try store.save(MacRecord(bogoID: bogoID, name: "Mac", keyAccount: "unused", approvalPublicKey: Data(),
                                 approverID: nil, biometryState: nil, state: .active, addedMs: 1, bootSeq: 1))
        let link = GroupedApprovalLink()
        let approver = PhoneApprover(directory: directory, link: link, clock: { 1000 })
        let group = ApprovalGroup(id: String(repeating: "a", count: 32), title: "Test purchase")
        for (bytes, request) in requests {
            precondition(bogoID == request.bogoID)
            precondition(approver.receive(bogoID, msgID: nil, .request(
                reqID: request.nonce, bootSeq: 1, bytes: bytes, pauseEpoch: 1, armDelayMs: 0, approvalGroup: group
            )))
        }

        switch CommandLine.arguments[2] {
        case "sync-during-dispatch":
            let winner = ids[0]
            let siblingID = approver.shown.first { $0.reqID == ids[1] }!.id
            precondition(approver.canApprove(approver.record(siblingID)!))
            await approver.becameActive()
            precondition(link.messages.contains { message in
                guard case .sync(let reqIDs) = message else { return false }
                return Set(reqIDs) == Set(ids)
            })
            precondition(approver.receive(bogoID, msgID: nil, .outcome(reqID: winner, outcome: .unknown)))
            precondition(approver.receive(bogoID, msgID: nil, .settled(reqID: winner)))
            let staleNotificationCanApprove = approver.canApprove(approver.record(siblingID)!)
            for loser in ids.dropFirst() {
                precondition(approver.receive(bogoID, msgID: nil, .ended(reqID: loser, why: .superseded)))
            }
            precondition(approver.receive(bogoID, msgID: nil, .outcome(reqID: winner, outcome: .executed)))
            let record = approver.shown.first { $0.reqID == winner }!
            guard !staleNotificationCanApprove, record.phase == .finished(nil, .executed) else {
                print("FAIL S1: old notification can approve after settlement = \(staleNotificationCanApprove), final winner phase = \(record.phase)")
                exit(1)
            }
        case "worker-disconnect":
            precondition(approver.receive(bogoID, msgID: nil, .ended(reqID: ids[0], why: .sessionClosed)))
            let entries = Inbox.entries(approver.shown, now: approver.nowMs)
            guard entries.count == 1, entries[0].live, Set(entries[0].records.map(\.reqID)) == Set(ids.dropFirst()) else {
                print("FAIL S2: expected one group entry with two live options, got \(entries.map { "live=\($0.live) options=\($0.count)" })")
                exit(1)
            }
        default:
            fatalError("Unknown test")
        }
    }
}
