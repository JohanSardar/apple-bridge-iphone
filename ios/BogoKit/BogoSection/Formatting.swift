import BogoModel
import BogoRelay
import Foundation
import SwiftUI

enum Formatting {
    static func visible(_ value: String, quoted: Bool = false) -> AttributedString {
        var result = AttributedString()
        if quoted { result += mark("“") }
        for segment in VisibleText.segments(value) {
            switch segment {
            case .text(let text):
                result += AttributedString(text)
            case .escape(let label):
                var escape = AttributedString(label)
                escape.foregroundColor = .orange
                escape.font = .caption.monospaced().weight(.semibold)
                result += escape
            }
        }
        if quoted { result += mark("”") }
        return result
    }

    static func prose(_ value: String) -> AttributedString {
        var result = AttributedString()
        for segment in VisibleText.segments(value) {
            switch segment {
            case .text(let text):
                result += AttributedString(text)
            case .escape("↵"):
                continue
            case .escape(let label):
                var escape = AttributedString(label)
                escape.foregroundColor = .orange
                escape.font = .caption.monospaced().weight(.semibold)
                result += escape
            }
        }
        return result
    }

    static func value(_ value: ArgumentValue) -> AttributedString {
        switch value {
        case .null: return keyword("null")
        case .bool(let flag): return keyword(flag ? "true" : "false")
        case .number(let text):
            var number = AttributedString(text)
            number.font = .body.monospacedDigit()
            return number
        case .string(let text): return visible(text, quoted: true)
        case .array(let items): return items.isEmpty ? keyword("[ ]") : mark(items.count == 1 ? "1 item" : "\(items.count) items")
        case .object(let members): return members.isEmpty ? keyword("{ }") : mark(members.count == 1 ? "1 field" : "\(members.count) fields")
        }
    }

    static func plain(_ value: ArgumentValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let text): return text
        case .string(let text): return text
        case .array(let items): return "\(items.count) items"
        case .object(let members): return "\(members.count) fields"
        }
    }

    static func action(_ review: Review) -> AttributedString {
        visible(service(review.request.upstream)) + AttributedString(" · ") + visible(humanize(review.action ?? review.request.tool))
    }

    static func title(_ review: Review) -> String {
        review.titleFromRole ? review.title : humanize(review.title)
    }

    static func service(_ upstream: String) -> String {
        let known = ["github": "GitHub", "gmail": "Gmail", "stripe": "Stripe", "link": "Link", "slack": "Slack", "openai": "OpenAI"]
        if let name = known[upstream.lowercased()] { return name }
        let spoken = words(upstream)
        return spoken.prefix(1).uppercased() + spoken.dropFirst()
    }

    static func humanize(_ identifier: String) -> String {
        var parts = words(identifier).split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return identifier }
        parts = parts.map { $0.count > 1 && $0 == $0.uppercased() ? $0 : $0.lowercased() }
        let verbs: Set = ["create", "update", "delete", "remove", "list", "get", "send", "cancel", "confirm", "retrieve", "search", "add", "set", "run", "pay", "post", "read", "write"]
        if parts.count > 1, verbs.contains(parts[parts.count - 1]), !verbs.contains(parts[0]) {
            parts.insert(parts.removeLast(), at: 0)
        }
        let joined = parts.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    static func summary(_ value: ArgumentValue) -> AttributedString {
        switch value {
        case .string(let text) where !text.isEmpty: return prose(text)
        case .bool(let flag): return AttributedString(flag ? "true" : "false")
        case .number(let text): return AttributedString(text)
        default: return self.value(value)
        }
    }

    static func list(_ labels: [String]) -> AttributedString {
        var result = AttributedString()
        for (index, label) in labels.enumerated() {
            if index > 0 { result += AttributedString(", ") }
            result += visible(label)
        }
        return result
    }

    static func fieldNames(_ highlights: [Review.Highlight]) -> [Int: String] {
        let names = highlights.map { highlight -> (Int, String) in
            guard case .key(let key)? = highlight.path.last else { return (highlight.id, highlight.label) }
            return (highlight.id, words(key))
        }
        let counts = Dictionary(grouping: names, by: { $0.1.lowercased() }).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: names.map { id, name in
            (id, counts[name.lowercased()] == 1 ? name : highlights.first { $0.id == id }?.label ?? name)
        })
    }

    static func words(_ key: String) -> String {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in key {
            if character == "_" || character == "-" || character == " " || character == "." {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let previous, previous.isLowercase || previous.isNumber {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        guard !words.isEmpty else { return key }
        let joined = words.map { $0.count > 1 && $0 == $0.uppercased() ? $0 : $0.lowercased() }.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    static func when(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func code(_ text: String) -> AttributedString {
        var code = AttributedString(text.replacingOccurrences(of: " ", with: "\u{00A0}"))
        code.font = .system(.callout, design: .monospaced).weight(.medium)
        code.foregroundColor = Ink.primary
        return code
    }

    static func ago(_ ms: UInt64, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince1970 - TimeInterval(ms) / 1000))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return when(Date(timeIntervalSince1970: TimeInterval(ms) / 1000), now: now)
    }

    static func remaining(_ until: Date, now: Date) -> String {
        let seconds = max(0, Int(until.timeIntervalSince(now).rounded(.up)))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func ended(_ why: EndReason) -> String {
        switch why {
        case .callEnded: return "The agent stopped waiting"
        case .sessionClosed: return "The agent disconnected"
        case .ownerCancel: return "Cancelled on the Mac"
        case .expired: return "Expired"
        case .agentRevoked: return "The agent was revoked"
        case .approverRevoked: return "This iPhone was revoked"
        case .agentPaused: return "Refused · agent paused"
        case .otherBoot: return "BOGO restarted"
        case .superseded: return "Another option was selected"
        case .unknown: return "Ended"
        }
    }

    static func outcome(_ outcome: Outcome) -> String {
        switch outcome {
        case .executed: return "Ran on the Mac"
        case .notSent: return "Not sent to the upstream"
        case .denied: return "Denied on the Mac"
        case .ended: return "Ended before it ran"
        case .unknown: return "Outcome unknown"
        case .noRecord: return "No record on the Mac"
        }
    }

    static func status(_ record: RequestRecord, now: UInt64) -> String? {
        switch record.phase {
        case .pending: return record.expired(at: now) ? "Expired" : nil
        case .sent(.approved): return record.approvalGroup == nil ? "Approved · sent to the Mac" : "Approval submitted"
        case .sent(.denied): return "Denied"
        case .settled(.approved?): return "Approved"
        case .settled: return "Decided on another approver"
        case .ended(.approved?, let why): return "Ended · " + ended(why)
        case .ended(.denied?, _): return "Denied"
        case .ended(nil, let why): return ended(why)
        case .finished(.approved?, let result) where !approvalStood(result):
            return outcome(result)
        case .finished(let decision, let result):
            let prefix = decision == .approved ? "Approved · " : decision == nil ? "" : "Denied · "
            return prefix + (prefix.isEmpty ? outcome(result) : outcome(result).lowercasedFirst)
        }
    }

    static func approvalStood(_ result: Outcome) -> Bool {
        result == .executed || result == .unknown
    }

    enum Mark {
        case approved, denied, ended, paused
    }

    static func history(_ record: RequestRecord) -> (text: String, mark: Mark) {
        switch record.phase {
        case .pending: return ("Waiting", .ended)
        case .sent(.approved): return record.approvalGroup == nil ? ("Approved · sending to the Mac", .approved) : ("Approval submitted", .ended)
        case .settled(.approved?): return ("Approved", .approved)
        case .finished(.approved?, let result):
            return approvalStood(result) ? ("Approved · " + outcome(result).lowercasedFirst, .approved) : (outcome(result), .ended)
        case .ended(.approved?, let why): return ("Ended · " + ended(why), .ended)
        case .sent(.denied(let note)), .settled(.denied(let note)?), .ended(.denied(let note)?, _), .finished(.denied(let note)?, _):
            return (note.map { "Denied · “\($0)”" } ?? "Denied", .denied)
        case .ended(nil, .agentPaused): return ("Refused while paused", .paused)
        case .ended(nil, let why): return (ended(why), .ended)
        case .settled(nil): return ("Decided on another approver", .ended)
        case .finished(nil, let result): return (outcome(result), .ended)
        }
    }

    private static func keyword(_ text: String) -> AttributedString {
        var word = AttributedString(text)
        word.font = .body.monospaced()
        word.foregroundColor = .secondary
        return word
    }

    private static func mark(_ text: String) -> AttributedString {
        var word = AttributedString(text)
        word.foregroundColor = .secondary
        return word
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
