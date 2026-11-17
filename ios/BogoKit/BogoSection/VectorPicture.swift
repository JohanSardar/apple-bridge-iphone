import CoreGraphics
import Foundation
import UIKit

enum VectorPicture {
    static let nodeLimit = 20_000
    static let depthLimit = 48
    static let useLimit = 4_000

    static func looksLikeSVG(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(1024), as: UTF8.self).lowercased()
        return head.contains("<svg")
    }

    static func image(_ data: Data, longestSide: CGFloat) -> UIImage? {
        guard let root = VectorTree.parse(data), root.name == "svg" else { return nil }
        var ids: [String: VectorNode] = [:]
        root.collectIDs(into: &ids)
        let box = viewBox(root)
        guard box.width > 0, box.height > 0, box.width.isFinite, box.height.isFinite else { return nil }
        let scale = longestSide / max(box.width, box.height)
        let size = CGSize(width: (box.width * scale).rounded(), height: (box.height * scale).rounded())
        guard size.width >= 1, size.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        var painter = VectorPainter(ids: ids)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -box.minX, y: -box.minY)
            painter.draw(root, in: cg, style: VectorStyle(), depth: 0)
        }
        return painter.drewSomething ? image : nil
    }

    static func viewBox(_ root: VectorNode) -> CGRect {
        let numbers = VectorNumbers.list(root.attributes["viewBox"] ?? "")
        if numbers.count == 4 { return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]) }
        let width = VectorNumbers.length(root.attributes["width"]) ?? 300
        let height = VectorNumbers.length(root.attributes["height"]) ?? 150
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

final class VectorNode {
    let name: String
    var attributes: [String: String]
    var children: [VectorNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func collectIDs(into ids: inout [String: VectorNode]) {
        if let id = attributes["id"], ids[id] == nil { ids[id] = self }
        for child in children { child.collectIDs(into: &ids) }
    }

    var href: String? {
        let link = attributes["href"] ?? attributes["xlink:href"]
        guard let link, link.hasPrefix("#") else { return nil }
        return String(link.dropFirst())
    }
}

final class VectorTree: NSObject, XMLParserDelegate {
    private var stack: [VectorNode] = []
    private var root: VectorNode?
    private var count = 0
    private var failed = false

    static func parse(_ data: Data) -> VectorNode? {
        let tree = VectorTree()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = tree
        guard parser.parse(), !tree.failed else { return nil }
        return tree.root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        count += 1
        guard count <= VectorPicture.nodeLimit, stack.count < VectorPicture.depthLimit else {
            failed = true
            parser.abortParsing()
            return
        }
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        var merged = attributes
        if let style = attributes["style"] {
            for declaration in style.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { merged[parts[0]] = parts[1] }
            }
        }
        let node = VectorNode(name: name, attributes: merged)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        nil
    }
}

enum VectorPaint {
    case none
    case color(CGColor)
    case reference(String)
}

struct VectorStyle {
    var fill: VectorPaint = .color(UIColor.black.cgColor)
    var stroke: VectorPaint = .none
    var strokeWidth: CGFloat = 1
    var fillOpacity: CGFloat = 1
    var strokeOpacity: CGFloat = 1
    var evenOdd = false
    var lineCap: CGLineCap = .butt
    var lineJoin: CGLineJoin = .miter
    var color: CGColor = UIColor.black.cgColor

    func inheriting(_ attributes: [String: String]) -> VectorStyle {
        var style = self
        if let value = attributes["color"], let color = VectorColors.parse(value, current: color) { style.color = color }
        if let value = attributes["fill"] { style.fill = VectorColors.paint(value, current: style.color) ?? style.fill }
        if let value = attributes["stroke"] { style.stroke = VectorColors.paint(value, current: style.color) ?? style.stroke }
        if let value = VectorNumbers.length(attributes["stroke-width"]) { style.strokeWidth = value }
        if let value = VectorNumbers.fraction(attributes["fill-opacity"]) { style.fillOpacity = value }
        if let value = VectorNumbers.fraction(attributes["stroke-opacity"]) { style.strokeOpacity = value }
        if let value = attributes["fill-rule"] { style.evenOdd = value == "evenodd" }
        switch attributes["stroke-linecap"] {
        case "round": style.lineCap = .round
        case "square": style.lineCap = .square
        case "butt": style.lineCap = .butt
        default: break
        }
        switch attributes["stroke-linejoin"] {
        case "round": style.lineJoin = .round
        case "bevel": style.lineJoin = .bevel
        case "miter": style.lineJoin = .miter
        default: break
        }
        return style
    }
}

struct VectorPainter {
    let ids: [String: VectorNode]
    var uses = 0
    var drewSomething = false
    private static let skipped: Set<String> = ["defs", "linearGradient", "radialGradient", "clipPath", "mask", "symbol", "title", "desc", "metadata",
                                               "style", "script", "text", "pattern", "filter", "marker", "foreignObject", "image", "a", "switch"]

    init(ids: [String: VectorNode]) {
        self.ids = ids
    }

    mutating func drawChildren(of node: VectorNode, in context: CGContext, style: VectorStyle, depth: Int) {
        for child in node.children { draw(child, in: context, style: style, depth: depth + 1) }
    }

    mutating func draw(_ node: VectorNode, in context: CGContext, style inherited: VectorStyle, depth: Int, asUse: Bool = false) {
        guard depth < VectorPicture.depthLimit, !(Self.skipped.contains(node.name) && !(asUse && node.name == "symbol")) else { return }
        if node.attributes["display"] == "none" || node.attributes["visibility"] == "hidden" { return }
        let style = inherited.inheriting(node.attributes)
        context.saveGState()
        defer { context.restoreGState() }
        if let transform = node.attributes["transform"] { context.concatenate(VectorTransforms.parse(transform)) }
        let opacity = VectorNumbers.fraction(node.attributes["opacity"]) ?? 1
        guard opacity > 0 else { return }
        let layered = opacity < 1
        if layered {
            context.setAlpha(opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer { if layered { context.endTransparencyLayer() } }
        switch node.name {
        case "svg", "g", "symbol":
            drawChildren(of: node, in: context, style: style, depth: depth)
        case "use":
            uses += 1
            guard uses <= VectorPicture.useLimit, let id = node.href, let target = ids[id] else { return }
            let x = VectorNumbers.length(node.attributes["x"]) ?? 0
            let y = VectorNumbers.length(node.attributes["y"]) ?? 0
            context.translateBy(x: x, y: y)
            draw(target, in: context, style: style, depth: depth + 1, asUse: true)
        default:
            guard let path = VectorShapes.path(node) else { return }
            paint(path, style: style, in: context)
        }
    }

    private mutating func paint(_ path: CGPath, style: VectorStyle, in context: CGContext) {
        guard !path.isEmpty else { return }
        fill(path, paint: style.fill, opacity: style.fillOpacity, evenOdd: style.evenOdd, in: context)
        if style.strokeWidth > 0 {
            let outline = path.copy(strokingWithWidth: style.strokeWidth, lineCap: style.lineCap, lineJoin: style.lineJoin, miterLimit: 4)
            fill(outline, paint: style.stroke, opacity: style.strokeOpacity, evenOdd: false, in: context)
        }
    }

    private mutating func fill(_ path: CGPath, paint: VectorPaint, opacity: CGFloat, evenOdd: Bool, in context: CGContext) {
        switch paint {
        case .none:
            return
        case .color(let color):
            context.addPath(path)
            context.setFillColor(color.copy(alpha: color.alpha * opacity) ?? color)
            context.fillPath(using: evenOdd ? .evenOdd : .winding)
            drewSomething = true
        case .reference(let id):
            guard let gradient = VectorGradient(id: id, ids: ids) else { return }
            context.saveGState()
            context.addPath(path)
            context.clip(using: evenOdd ? .evenOdd : .winding)
            context.setAlpha(opacity)
            gradient.draw(in: context, bounds: path.boundingBoxOfPath)
            context.restoreGState()
            drewSomething = true
        }
    }
}

struct VectorGradient {
    let radial: Bool
    let attributes: [String: String]
    let stops: [(offset: CGFloat, color: CGColor)]

    init?(id: String, ids: [String: VectorNode]) {
        var node = ids[id]
        var attributes: [String: String] = [:]
        var stops: [(CGFloat, CGColor)] = []
        var radial: Bool?
        var hops = 0
        while let current = node, hops < 8 {
            guard current.name == "linearGradient" || current.name == "radialGradient" else { return nil }
            if radial == nil { radial = current.name == "radialGradient" }
            for (key, value) in current.attributes where attributes[key] == nil { attributes[key] = value }
            if stops.isEmpty {
                for stop in current.children where stop.name == "stop" {
                    let offset = VectorNumbers.fraction(stop.attributes["offset"]) ?? 0
                    let base = VectorColors.parse(stop.attributes["stop-color"] ?? "black", current: UIColor.black.cgColor) ?? UIColor.black.cgColor
                    let alpha = VectorNumbers.fraction(stop.attributes["stop-opacity"]) ?? 1
                    stops.append((offset, base.copy(alpha: base.alpha * alpha) ?? base))
                }
            }
            node = current.href.flatMap { ids[$0] }
            hops += 1
        }
        guard let radial, !stops.isEmpty else { return nil }
        self.radial = radial
        self.attributes = attributes
        self.stops = stops
    }

    func draw(in context: CGContext, bounds: CGRect) {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var offsets: [CGFloat] = []
        var colors: [CGColor] = []
        var last: CGFloat = 0
        for stop in stops {
            last = max(last, min(1, max(0, stop.offset)))
            offsets.append(last)
            colors.append(stop.color.converted(to: space, intent: .defaultIntent, options: nil) ?? stop.color)
        }
        if colors.count == 1 {
            colors.append(colors[0])
            offsets = [0, 1]
        }
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: offsets) else { return }
        let user = attributes["gradientUnits"] == "userSpaceOnUse"
        if !user {
            guard bounds.width > 0, bounds.height > 0 else { return }
            context.concatenate(CGAffineTransform(a: bounds.width, b: 0, c: 0, d: bounds.height, tx: bounds.minX, ty: bounds.minY))
        }
        if let transform = attributes["gradientTransform"] { context.concatenate(VectorTransforms.parse(transform)) }
        func value(_ key: String, _ fallback: CGFloat) -> CGFloat {
            guard let text = attributes[key] else { return fallback }
            if text.hasSuffix("%"), let number = Double(text.dropLast()) { return CGFloat(number) / 100 }
            return VectorNumbers.length(text) ?? fallback
        }
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        if radial {
            let cx = value("cx", 0.5), cy = value("cy", 0.5), r = value("r", 0.5)
            let fx = value("fx", cx), fy = value("fy", cy)
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: fx, y: fy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: options)
        } else {
            let start = CGPoint(x: value("x1", 0), y: value("y1", 0))
            let end = CGPoint(x: value("x2", 1), y: value("y2", 0))
            context.drawLinearGradient(gradient, start: start, end: end, options: options)
        }
    }
}

enum VectorShapes {
    static func path(_ node: VectorNode) -> CGPath? {
        let a = node.attributes
        func number(_ key: String) -> CGFloat { VectorNumbers.length(a[key]) ?? 0 }
        switch node.name {
        case "path":
            return VectorPathData.parse(a["d"] ?? "")
        case "rect":
            let rect = CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height"))
            guard rect.width > 0, rect.height > 0 else { return nil }
            var rx = VectorNumbers.length(a["rx"]), ry = VectorNumbers.length(a["ry"])
            if rx == nil { rx = ry }
            if ry == nil { ry = rx }
            let radiusX = min(rx ?? 0, rect.width / 2), radiusY = min(ry ?? 0, rect.height / 2)
            return radiusX > 0 && radiusY > 0 ? CGPath(roundedRect: rect, cornerWidth: radiusX, cornerHeight: radiusY, transform: nil) : CGPath(rect: rect, transform: nil)
        case "circle":
            let r = number("r")
            guard r > 0 else { return nil }
            return CGPath(ellipseIn: CGRect(x: number("cx") - r, y: number("cy") - r, width: 2 * r, height: 2 * r), transform: nil)
        case "ellipse":
            let rx = number("rx"), ry = number("ry")
            guard rx > 0, ry > 0 else { return nil }
            return CGPath(ellipseIn: CGRect(x: number("cx") - rx, y: number("cy") - ry, width: 2 * rx, height: 2 * ry), transform: nil)
        case "line":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: number("x1"), y: number("y1")))
            path.addLine(to: CGPoint(x: number("x2"), y: number("y2")))
            return path
        case "polyline", "polygon":
            let values = VectorNumbers.list(a["points"] ?? "")
            guard values.count >= 4 else { return nil }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: values[0], y: values[1]))
            var index = 2
            while index + 1 < values.count {
                path.addLine(to: CGPoint(x: values[index], y: values[index + 1]))
                index += 2
            }
            if node.name == "polygon" { path.closeSubpath() }
            return path
        default:
            return nil
        }
    }
}

struct VectorPathData {
    private let bytes: [UInt8]
    private var index = 0

    static func parse(_ text: String) -> CGPath? {
        var parser = VectorPathData(bytes: Array(text.utf8))
        return parser.run()
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private mutating func run() -> CGPath? {
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var control: CGPoint?
        var quadratic: CGPoint?
        var command: UInt8 = 0
        var started = false
        while true {
            skipSeparators()
            guard index < bytes.count else { break }
            let byte = bytes[index]
            if isCommand(byte) {
                command = byte
                index += 1
            } else if command == 0 {
                return nil
            }
            let relative = command >= 97
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command | 0x20 {
            case UInt8(ascii: "m"):
                guard let x = number(), let y = number() else { return started ? path : nil }
                current = point(x, y)
                start = current
                path.move(to: current)
                started = true
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
                control = nil
                quadratic = nil
            case UInt8(ascii: "l"):
                guard started, let x = number(), let y = number() else { return started ? path : nil }
                current = point(x, y)
                path.addLine(to: current)
                control = nil
                quadratic = nil
            case UInt8(ascii: "h"):
                guard started, let x = number() else { return started ? path : nil }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                control = nil
                quadratic = nil
            case UInt8(ascii: "v"):
                guard started, let y = number() else { return started ? path : nil }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                control = nil
                quadratic = nil
            case UInt8(ascii: "c"):
                guard started, let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return path }
                let first = point(x1, y1), second = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: first, control2: second)
                control = second
                quadratic = nil
                current = end
            case UInt8(ascii: "s"):
                guard started, let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return path }
                let first = control.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let second = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: first, control2: second)
                control = second
                quadratic = nil
                current = end
            case UInt8(ascii: "q"):
                guard started, let x1 = number(), let y1 = number(), let x = number(), let y = number() else { return path }
                let pivot = point(x1, y1), end = point(x, y)
                path.addQuadCurve(to: end, control: pivot)
                quadratic = pivot
                control = nil
                current = end
            case UInt8(ascii: "t"):
                guard started, let x = number(), let y = number() else { return path }
                let pivot = quadratic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = point(x, y)
                path.addQuadCurve(to: end, control: pivot)
                quadratic = pivot
                control = nil
                current = end
            case UInt8(ascii: "a"):
                guard started, let rx = number(), let ry = number(), let angle = number(), let large = flag(), let sweep = flag(), let x = number(), let y = number() else { return path }
                let end = point(x, y)
                VectorArc.add(to: path, from: current, to: end, rx: rx, ry: ry, angle: angle, large: large, sweep: sweep)
                current = end
                control = nil
                quadratic = nil
            case UInt8(ascii: "z"):
                guard started else { return nil }
                path.closeSubpath()
                current = start
                control = nil
                quadratic = nil
                skipSeparators()
                if index < bytes.count, !isCommand(bytes[index]) { return path }
            default:
                return started ? path : nil
            }
        }
        return started ? path : nil
    }

    private func isCommand(_ byte: UInt8) -> Bool {
        "MmLlHhVvCcSsQqTtAaZz".utf8.contains(byte)
    }

    private mutating func skipSeparators() {
        while index < bytes.count, bytes[index] == 32 || bytes[index] == 44 || (9...13).contains(bytes[index]) { index += 1 }
    }

    private mutating func flag() -> Bool? {
        skipSeparators()
        guard index < bytes.count, bytes[index] == 48 || bytes[index] == 49 else { return nil }
        defer { index += 1 }
        return bytes[index] == 49
    }

    private mutating func number() -> CGFloat? {
        skipSeparators()
        let begin = index
        if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
        var digits = 0
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1; digits += 1 }
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1; digits += 1 }
        }
        guard digits > 0 else {
            index = begin
            return nil
        }
        if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
            let mark = index
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            var exponent = 0
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1; exponent += 1 }
            if exponent == 0 { index = mark }
        }
        guard let value = Double(String(decoding: bytes[begin..<index], as: UTF8.self)), value.isFinite else { return nil }
        return CGFloat(value)
    }
}

enum VectorArc {
    static func add(to path: CGMutablePath, from start: CGPoint, to end: CGPoint, rx: CGFloat, ry: CGFloat, angle: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, start != end else {
            path.addLine(to: end)
            return
        }
        let phi = angle * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : sqrt(max(0, numerator / denominator))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2
        func angleBetween(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = (ux * vx + uy * vy) / (sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy))
            return sign * acos(min(1, max(-1, dot)))
        }
        let theta = angleBetween(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angleBetween((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let kappa = 4 / 3 * tan(step / 4)
        var t = theta
        func pointAt(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi, y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi, y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        for _ in 0..<segments {
            let p0 = pointAt(t), p3 = pointAt(t + step)
            let d0 = derivative(t), d3 = derivative(t + step)
            path.addCurve(to: p3, control1: CGPoint(x: p0.x + kappa * d0.x, y: p0.y + kappa * d0.y), control2: CGPoint(x: p3.x - kappa * d3.x, y: p3.y - kappa * d3.y))
            t += step
        }
    }
}

enum VectorTransforms {
    static func parse(_ text: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        for match in text.matches(of: #/([a-zA-Z]+)\s*\(([^)]*)\)/#) {
            let values = VectorNumbers.list(String(match.output.2))
            var next = CGAffineTransform.identity
            switch match.output.1 {
            case "matrix" where values.count == 6:
                next = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            case "translate" where !values.isEmpty:
                next = CGAffineTransform(translationX: values[0], y: values.count > 1 ? values[1] : 0)
            case "scale" where !values.isEmpty:
                next = CGAffineTransform(scaleX: values[0], y: values.count > 1 ? values[1] : values[0])
            case "rotate" where !values.isEmpty:
                let radians = values[0] * .pi / 180
                if values.count == 3 {
                    next = CGAffineTransform(translationX: values[1], y: values[2]).rotated(by: radians).translatedBy(x: -values[1], y: -values[2])
                } else {
                    next = CGAffineTransform(rotationAngle: radians)
                }
            case "skewX" where !values.isEmpty:
                next = CGAffineTransform(a: 1, b: 0, c: tan(values[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where !values.isEmpty:
                next = CGAffineTransform(a: 1, b: tan(values[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                continue
            }
            result = next.concatenating(result)
        }
        return result
    }
}

enum VectorNumbers {
    static func list(_ text: String) -> [CGFloat] {
        text.matches(of: #/[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/#).compactMap { Double($0.output).map { CGFloat($0) } }.filter(\.isFinite)
    }

    static func length(_ text: String?) -> CGFloat? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.hasSuffix("%") else { return nil }
        let trimmed = ["px", "pt"].reduce(text) { $0.hasSuffix($1) ? String($0.dropLast(2)) : $0 }
        return Double(trimmed).map { CGFloat($0) }.flatMap { $0.isFinite ? $0 : nil }
    }

    static func fraction(_ text: String?) -> CGFloat? {
        guard let text = text?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasSuffix("%"), let value = Double(text.dropLast()) { return min(1, max(0, CGFloat(value) / 100)) }
        return Double(text).map { min(1, max(0, CGFloat($0))) }
    }
}

enum VectorColors {
    static let named: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "lime": 0x00FF00, "blue": 0x0000FF, "yellow": 0xFFFF00,
        "orange": 0xFFA500, "gray": 0x808080, "grey": 0x808080, "silver": 0xC0C0C0, "purple": 0x800080, "navy": 0x000080, "teal": 0x008080,
        "maroon": 0x800000, "olive": 0x808000, "aqua": 0x00FFFF, "cyan": 0x00FFFF, "fuchsia": 0xFF00FF, "magenta": 0xFF00FF, "brown": 0xA52A2A,
        "pink": 0xFFC0CB, "gold": 0xFFD700, "darkgray": 0xA9A9A9, "lightgray": 0xD3D3D3, "darkgreen": 0x006400, "darkblue": 0x00008B,
    ]

    static func paint(_ text: String, current: CGColor) -> VectorPaint? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value == "none" || value == "transparent" { return VectorPaint.none }
        if value.hasPrefix("url(") {
            let inner = value.dropFirst(4).prefix { $0 != ")" }.trimmingCharacters(in: CharacterSet(charactersIn: "'\" #"))
            return .reference(inner)
        }
        return parse(value, current: current).map(VectorPaint.color)
    }

    static func parse(_ text: String, current: CGColor) -> CGColor? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value == "currentcolor" { return current }
        if value.hasPrefix("#") {
            let hex = String(value.dropFirst())
            guard let number = UInt32(hex, radix: 16) else { return nil }
            switch hex.count {
            case 3:
                let r = number >> 8 & 0xF, g = number >> 4 & 0xF, b = number & 0xF
                return UIColor(hex: r * 0x110000 + g * 0x1100 + b * 0x11, alpha: 1).cgColor
            case 6:
                return UIColor(hex: number, alpha: 1).cgColor
            default:
                return nil
            }
        }
        if value.hasPrefix("rgb") {
            let parts = value.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            func channel(_ part: String) -> CGFloat? {
                if part.hasSuffix("%") { return Double(part.dropLast()).map { CGFloat($0) / 100 } }
                return Double(part).map { CGFloat($0) / 255 }
            }
            guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
            let alpha = parts.count > 3 ? VectorNumbers.fraction(parts[3]) ?? 1 : 1
            return UIColor(red: r, green: g, blue: b, alpha: alpha).cgColor
        }
        return named[value].map { UIColor(hex: $0, alpha: 1).cgColor }
    }
}
