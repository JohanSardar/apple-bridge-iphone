#if DEBUG
import BogoModel
import Foundation

public enum DemoRequest: String, CaseIterable, Sendable {
    case linkPurchase = "link-purchase"
    case email
    case noRoles = "no-roles"
    case mismatch

    public var title: String {
        switch self {
        case .linkPurchase: return "Link purchase"
        case .email: return "Email send"
        case .noRoles: return "Deploy, no roles"
        case .mismatch: return "Purchase with mismatch"
        }
    }

    struct Hint {
        let path: [PathElement]
        let format: DisplayFormat
    }

    struct Shape {
        let upstream: String
        let tool: String
        let arguments: DemoValue
        let justification: String
        let hints: [Hint]
        let agentID: Data
        let agentName: String
        let clientName: String
        let expiresInMs: UInt64?
    }

    static let shoppingAgent = Data([0x5a, 0x0b, 0x14, 0x6e, 0x31, 0xc2, 0x77, 0x90, 0x08, 0xd4, 0x4f, 0x6a, 0x12, 0xe9, 0x3b, 0x71])
    static let mailAgent = Data([0x3e, 0x91, 0x0c, 0xa5, 0x5d, 0x22, 0x6f, 0x18, 0xb7, 0x40, 0x9a, 0x03, 0xee, 0x61, 0x2c, 0x84])
    static let releaseAgent = Data([0x71, 0x4d, 0x2a, 0x93, 0x06, 0xbf, 0x58, 0xe1, 0x9c, 0x37, 0x15, 0xa8, 0x60, 0xd2, 0x0e, 0x4b])

    var shape: Shape {
        switch self {
        case .linkPurchase:
            return Shape(
                upstream: "stripe", tool: "call_write_tool",
                arguments: .object([
                    member("arguments", .object([
                        member("amount", .number("1199")),
                        member("context", .string("The user asked for a fun, quirky desk toy for their home office with a total budget of $20. They picked the classic Rubik’s Cube from the search results. Ship to the default address on file.")),
                        member("currency", .string("usd")),
                        member("lineItem", .array([.object([
                            member("image_url", .string("https://upload.wikimedia.org/wikipedia/commons/a/a6/Rubik%27s_cube.svg")),
                            member("name", .string("Classic 3x3 Rubik's Cube")),
                            member("quantity", .number("1")),
                            member("unit_amount", .number("1199")),
                        ])])),
                        member("merchantName", .string("Amazon")),
                        member("test", .bool(true)),
                    ])),
                    member("name", .string("spend-request_create")),
                ]),
                justification: "Buying the Rubik’s Cube the user picked for their desk.",
                hints: [
                    Hint(path: [.key("name")], format: .text),
                    Hint(path: [.key("arguments"), .key("lineItem"), .index(0), .key("name")], format: .title),
                    Hint(path: [.key("arguments"), .key("lineItem"), .index(0), .key("image_url")], format: .image),
                    Hint(path: [.key("arguments"), .key("merchantName")], format: .subtitle),
                    Hint(path: [.key("arguments"), .key("amount")], format: .moneyMinor("USD")),
                    Hint(path: [.key("arguments"), .key("context")], format: .text),
                    Hint(path: [.key("arguments"), .key("test")], format: .text),
                ],
                agentID: Self.shoppingAgent, agentName: "Shopping agent", clientName: "claude-code", expiresInMs: nil)
        case .email:
            return Shape(
                upstream: "gmail", tool: "send_email",
                arguments: .object([
                    member("bcc", .array([])),
                    member("body", .string("Hi Maya,\n\nAre you free for dinner on Friday at 7? I booked a table at Luka’s.\n\nSam")),
                    member("cc", .array([])),
                    member("subject", .string("Dinner on Friday?")),
                    member("to", .string("maya@example.com")),
                ]),
                justification: "The user asked me to invite Maya to dinner on Friday at 7.",
                hints: [
                    Hint(path: [.key("subject")], format: .title),
                    Hint(path: [.key("to")], format: .subtitle),
                    Hint(path: [.key("body")], format: .text),
                ],
                agentID: Self.mailAgent, agentName: "Inbox assistant", clientName: "claude-code", expiresInMs: 900_000)
        case .noRoles:
            return Shape(
                upstream: "github", tool: "create_deployment",
                arguments: .object([
                    member("environment", .string("production")),
                    member("ref", .string("main")),
                    member("repo", .string("acme/web")),
                ]),
                justification: "Ship the checkout fix the user approved in chat.",
                hints: [
                    Hint(path: [.key("environment")], format: .text),
                    Hint(path: [.key("repo")], format: .text),
                ],
                agentID: Self.releaseAgent, agentName: "Release bot", clientName: "codex", expiresInMs: nil)
        case .mismatch:
            return Shape(
                upstream: "stripe", tool: "call_write_tool",
                arguments: .object([
                    member("arguments", .object([
                        member("amount", .number("50000")),
                        member("currency", .string("usd")),
                        member("lineItem", .array([.object([
                            member("image_url", .string("https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=900")),
                            member("name", .string("Wireless noise-cancelling headphones")),
                            member("quantity", .number("1")),
                        ])])),
                        member("merchantName", .string("Best Buy")),
                        member("test", .bool(true)),
                    ])),
                    member("name", .string("spend-request_create")),
                ]),
                justification: "just a small $5 test charge",
                hints: [
                    Hint(path: [.key("name")], format: .text),
                    Hint(path: [.key("arguments"), .key("lineItem"), .index(0), .key("name")], format: .title),
                    Hint(path: [.key("arguments"), .key("lineItem"), .index(0), .key("image_url")], format: .image),
                    Hint(path: [.key("arguments"), .key("merchantName")], format: .subtitle),
                    Hint(path: [.key("arguments"), .key("amount")], format: .moneyMinor("USD")),
                    Hint(path: [.key("arguments"), .key("test")], format: .text),
                ],
                agentID: Self.shoppingAgent, agentName: "Shopping agent", clientName: "claude-code", expiresInMs: nil)
        }
    }

    func bytes(bogoID: Data, session: Data, nonce: Data, nowMs: UInt64) -> Data {
        let shape = shape
        var writer = DemoWriter()
        writer.raw(RequestBytes.magic)
        writer.u16(UInt16(RequestBytes.version))
        writer.tag(1); writer.bytes(bogoID)
        writer.tag(2); writer.string(shape.upstream)
        writer.tag(3); writer.string(shape.tool)
        writer.tag(4); writer.u8(1); writer.value(shape.arguments)
        writer.tag(5); writer.u8(1); writer.string(shape.justification)
        writer.tag(6); writer.u32(UInt32(shape.hints.count))
        for hint in shape.hints {
            writer.u32(UInt32(hint.path.count))
            for element in hint.path {
                switch element {
                case .key(let key): writer.u8(0); writer.string(key)
                case .index(let index): writer.u8(1); writer.u32(index)
                }
            }
            switch hint.format {
            case .text: writer.u8(0)
            case .moneyMinor(let currency): writer.u8(1); writer.string(currency)
            case .title: writer.u8(2)
            case .subtitle: writer.u8(3)
            case .image: writer.u8(4)
            }
        }
        writer.tag(7); writer.bytes(shape.agentID)
        writer.tag(8); writer.string(shape.agentName)
        writer.tag(9); writer.u8(1); writer.string(shape.clientName)
        writer.tag(10); writer.bytes(session)
        writer.tag(11); writer.bytes(nonce)
        writer.tag(12); writer.u64(nowMs)
        writer.tag(13)
        if let lifetime = shape.expiresInMs {
            writer.u8(1); writer.u64(nowMs + lifetime)
        } else {
            writer.u8(0)
        }
        return writer.data
    }
}

indirect enum DemoValue {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([DemoValue])
    case object([(key: String, value: DemoValue)])
}

private func member(_ key: String, _ value: DemoValue) -> (key: String, value: DemoValue) {
    (key, value)
}

struct DemoWriter {
    var data = Data()

    mutating func raw(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }
    mutating func u8(_ value: UInt8) { data.append(value) }
    mutating func tag(_ value: UInt8) { data.append(value) }
    mutating func u16(_ value: UInt16) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
    mutating func u32(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
    mutating func u64(_ value: UInt64) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }

    mutating func bytes(_ value: Data) {
        u32(UInt32(value.count))
        data.append(value)
    }

    mutating func string(_ value: String) {
        bytes(Data(value.utf8))
    }

    mutating func value(_ value: DemoValue) {
        switch value {
        case .null: u8(0)
        case .bool(let flag): u8(flag ? 2 : 1)
        case .number(let text): u8(3); string(text)
        case .string(let text): u8(4); string(text)
        case .array(let items):
            u8(5)
            u32(UInt32(items.count))
            for item in items { self.value(item) }
        case .object(let members):
            u8(6)
            let sorted = members.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            u32(UInt32(sorted.count))
            for member in sorted {
                string(member.key)
                self.value(member.value)
            }
        }
    }
}
#endif
