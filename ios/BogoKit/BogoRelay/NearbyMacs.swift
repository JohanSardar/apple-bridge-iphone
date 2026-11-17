import BogoModel
import Foundation
import Network

@MainActor
final class NearbyMacs {
    struct Found: Equatable {
        let name: String
        let code: PairCode
        let seen: Date
        var id: String { Hex.string(code.room) }
    }

    static let service = "_bogo-pair._tcp"

    private var browser: NWBrowser?
    private var found: [Found] = []
    private var asked = ContinuousClock.now
    private var idle: Task<Void, Never>?

    func current() -> [Found] {
        asked = .now
        if browser == nil { start() }
        return found
    }

    func stop() {
        browser?.cancel()
        browser = nil
        found = []
        idle?.cancel()
        idle = nil
    }

    private func start() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.service, domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in
            let listed = results.compactMap(Self.listed)
            Task { @MainActor [weak self] in self?.update(listed) }
        }
        browser.stateUpdateHandler = { state in
            guard case .failed = state else { return }
            Task { @MainActor [weak self] in self?.stop() }
        }
        browser.start(queue: .main)
        self.browser = browser
        idle = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if ContinuousClock.now - self.asked > .seconds(5) {
                    self.stop()
                    return
                }
            }
        }
    }

    private func update(_ listed: [(name: String, code: PairCode)]) {
        let before = Dictionary(found.map { ($0.id, $0.seen) }, uniquingKeysWith: { first, _ in first })
        found = listed.map { Found(name: $0.name, code: $0.code, seen: before[Hex.string($0.code.room)] ?? Date()) }
            .sorted { ($0.seen, $0.name) < ($1.seen, $1.name) }
    }

    private nonisolated static func listed(_ result: NWBrowser.Result) -> (name: String, code: PairCode)? {
        guard case .service(let name, _, _, _) = result.endpoint, case .bonjour(let txt) = result.metadata,
              let text = txt["c"], let code = PairCode(text) else { return nil }
        return (name, code)
    }
}
