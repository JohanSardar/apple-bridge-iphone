import Foundation

@main
enum BogoVectorsProof {
    static func tagged(_ value: ArgumentValue) -> Any {
        switch value {
        case .null: return ["null"]
        case .bool(let flag): return ["bool", flag]
        case .number(let text): return ["num", text]
        case .string(let text): return ["str", text]
        case .array(let items): return ["arr", items.map(tagged)]
        case .object(let members): return ["obj", members.map { [$0.key, tagged($0.value)] }]
        }
    }

    static func tagged(_ hint: DisplayHint) -> Any {
        let path: [Any] = hint.path.map { element -> Any in
            switch element {
            case .key(let key): return ["key": key]
            case .index(let index): return ["index": String(index)]
            }
        }
        let format: Any
        switch hint.format {
        case .text: format = "text"
        case .title: format = "title"
        case .subtitle: format = "subtitle"
        case .image: format = "image"
        case .moneyMinor(let currency): format = ["money_minor": currency]
        }
        return ["path": path, "format": format]
    }

    static func fields(_ request: ApprovalRequest) -> [String: Any] {
        [
            "bogo_id_hex": Hex.string(request.bogoID),
            "upstream": request.upstream,
            "tool": request.tool,
            "args": request.arguments.map(tagged) ?? NSNull(),
            "justification": request.justification ?? NSNull(),
            "hints": request.hints.map(tagged),
            "agent_id_hex": Hex.string(request.agentID),
            "agent_name": request.agentName,
            "client_name": request.clientName ?? NSNull(),
            "session_hex": Hex.string(request.session),
            "nonce_hex": Hex.string(request.nonce),
            "created_ms": String(request.createdMs),
            "expires_ms": request.expiresMs.map(String.init) ?? NSNull(),
        ]
    }

    static func load(_ directory: URL, _ file: String, _ key: String) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root[key] as? [[String: Any]] else {
            fatalError("Fixture must load \(file)")
        }
        return list
    }

    static func main() {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        var failures: [String] = []
        var requests: [String: ApprovalRequest] = [:]
        let accepted = load(directory, "requests.json", "requests")
        for vector in accepted {
            let name = vector["name"] as! String
            let bytes = Hex.data(vector["encoded_hex"] as! String)!
            guard let request = RequestBytes.decode(bytes) else {
                failures.append("\(name): decoder refused a valid request")
                continue
            }
            requests[name] = request
            let expected = vector["decoded"] as! [String: Any]
            for (field, value) in fields(request) where !NSDictionary(dictionary: [field: value]).isEqual(to: [field: expected[field] ?? NSNull()]) {
                failures.append("\(name): \(field) decoded as \(value), vector says \(expected[field] ?? "nothing")")
            }
            if Hex.string(RequestBytes.signedMessage(bytes)) != vector["signed_message_hex"] as! String {
                failures.append("\(name): signed message differs from the vector")
            }
        }
        let rejected = load(directory, "decode_reject.json", "reject")
        for vector in rejected {
            let name = vector["name"] as! String
            if let bytes = Hex.data(vector["hex"] as! String), RequestBytes.decode(bytes) != nil {
                failures.append("\(name): decoder accepted bytes it must refuse")
            }
        }
        let scenarios: [(String, String, Bool)] = [
            ("payment-approved", "$47.00", false),
            ("amount-4701", "$47.01", true),
            ("lie-in-reason", "$500.00", true),
        ]
        for (name, price, warns) in scenarios {
            guard let request = requests[name] else {
                failures.append("\(name): vector missing")
                continue
            }
            let review = Review(request)
            if case .money(let amount, _)? = review.price?.value, amount.formatted == price {} else {
                failures.append("\(name): review must show \(price), shows \(String(describing: review.price?.value))")
            }
            if review.warnings.isEmpty == warns {
                failures.append("\(name): review warnings \(review.warnings), expected \(warns ? "a mismatch" : "none")")
            }
        }
        guard failures.isEmpty else {
            failures.forEach { print("FAIL \($0)") }
            exit(1)
        }
        print("PASS \(accepted.count) requests, \(rejected.count) rejects, \(scenarios.count) reviews")
    }
}
