import ActivityKit
import CryptoKit
import Foundation
import WidgetKit

@MainActor
enum WidgetsCapability {
    static let descriptor = Capability(id: "widgets", title: "Live Activities and widgets", permission: "Enable to share ActivityKit push tokens", available: true, deferredHandlers: [
        "iphone.live.start": { try await apply($0, ending: false) },
        "iphone.live.update": { try await apply($0, ending: false) },
        "iphone.live.end": { try await apply($0, ending: true) },
    ])
    private static var observers: [Task<Void, Never>] = []
    private static var activityIDs: Set<String> = []

    static func resume() {
        guard observers.isEmpty, UserDefaults.standard.bool(forKey: "capability.widgets.enabled") else { return }
        observers.append(Task { @MainActor in
            for await token in Activity<AgentTaskAttributes>.pushToStartTokenUpdates {
                await register(token, task: "_start")
            }
        })
        observers.append(Task { @MainActor in
            for await activity in Activity<AgentTaskAttributes>.activityUpdates {
                observe(activity)
            }
        })
        for activity in Activity<AgentTaskAttributes>.activities { observe(activity) }
    }

    private static func observe(_ activity: Activity<AgentTaskAttributes>) {
        guard activityIDs.insert(activity.id).inserted else { return }
        observers.append(Task { @MainActor in await registerActivity(activity) })
        observers.append(Task { @MainActor in
            for await state in activity.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    await register(Data(), task: activity.attributes.taskID)
                    activityIDs.remove(activity.id)
                    return
                }
            }
        })
    }

    static func disable() {
        for observer in observers { observer.cancel() }
        observers = []
        activityIDs = []
        Task {
            if let identity = try? DeviceIdentity.load() {
                _ = try? await PairingClient.signedRequest(identity: identity, path: "/v1/iphone/live-disable")
            }
            for activity in Activity<AgentTaskAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func registerActivity(_ activity: Activity<AgentTaskAttributes>) async {
        for await token in activity.pushTokenUpdates {
            await register(token, task: activity.attributes.taskID)
        }
    }

    private static func register(_ token: Data, task: String) async {
        while !Task.isCancelled && UserDefaults.standard.bool(forKey: "capability.widgets.enabled") {
            do {
                let identity = try DeviceIdentity.load()
                let payload = try JSONSerialization.data(withJSONObject: ["task_id": task, "token": token.map { String(format: "%02x", $0) }.joined()])
                _ = try await PairingClient.signedRequest(identity: identity, path: "/v1/iphone/live-token", payload: payload)
                return
            } catch {
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private static func apply(_ job: PhoneJob, ending: Bool) async throws -> Data? {
        let arguments = job.command.args
        guard case .string(let task) = arguments["task_id"], case .string(let title) = arguments["title"] else { throw IdentityError.requestFailed }
        var status = ""
        if case .string(let value) = arguments["status"] { status = value }
        var progress = 0.0
        if case .number(let value) = arguments["progress"] { progress = value }
        let encryption = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: DeviceIdentity.load().encryption).publicKey.rawRepresentation
        let handle = PairingClient.liveHandle(encryptionKey: encryption, task: task)
        let content = ActivityContent(state: AgentTaskAttributes.ContentState(status: status, progress: progress, title: title), staleDate: nil)
        for attempt in 0..<20 {
            for activity in Activity<AgentTaskAttributes>.activities where activity.attributes.taskID == handle || activity.attributes.taskID == task {
                if ending { await activity.end(content, dismissalPolicy: .default) } else { await activity.update(content) }
                return Data(#"{"applied":true}"#.utf8)
            }
            if ending { return Data(#"{"applied":false}"#.utf8) }
            if attempt < 19 { try await Task.sleep(for: .milliseconds(500)) }
        }
        throw IdentityError.requestFailed
    }

    static func status(_ value: String) {
        BridgeStatus(status: value, updated: Date()).save()
        WidgetCenter.shared.reloadTimelines(ofKind: "BridgeStatus")
    }
}
