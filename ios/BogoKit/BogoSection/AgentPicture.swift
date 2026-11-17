import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PictureLoad: Sendable {
    case loading
    case shown(UIImage)
    case unavailable(String)
}

@MainActor
@Observable
final class Pictures {
    static let shared = Pictures()
    private static let kept = 24

    private(set) var loads: [String: PictureLoad] = [:]
    private var order: [String] = []

    func load(_ link: String) {
        guard loads[link] == nil else { return }
        loads[link] = .loading
        order.append(link)
        while order.count > Self.kept { loads[order.removeFirst()] = nil }
        Task {
            let result = await PictureFetch.picture(link)
            if loads[link] != nil { loads[link] = result }
        }
    }
}

enum PictureFetch {
    static let byteLimit = 5_000_000
    static let pixelLimit = 30_000_000
    static let shownPixels = 1400
    static let formats: [UTType] = [.jpeg, .png, .heic, .heif, .gif, .webP]

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.httpAdditionalHeaders = ["Accept": "image/jpeg, image/png, image/heic, image/gif, image/webp, image/svg+xml", "Accept-Language": "en"]
        return URLSession(configuration: configuration, delegate: PictureGuard(), delegateQueue: nil)
    }()

    static func picture(_ link: String) async -> PictureLoad {
        guard let url = URL(string: link, encodingInvalidCharacters: false), url.host()?.isEmpty == false,
              url.user() == nil, url.password() == nil else { return .unavailable("not a valid link") }
        guard url.scheme?.lowercased() == "https" else { return .unavailable("not https") }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { return .unavailable("couldn’t load") }
            guard http.statusCode == 200 else {
                return .unavailable((300..<400).contains(http.statusCode) ? "redirected off https" : "error \(http.statusCode)")
            }
            let type = http.mimeType?.lowercased() ?? ""
            guard type.hasPrefix("image/") else { return .unavailable("not an image") }
            guard http.expectedContentLength <= byteLimit else { return .unavailable("over 5 MB") }
            var data = Data()
            data.reserveCapacity(max(0, Int(http.expectedContentLength)))
            for try await byte in bytes {
                data.append(byte)
                if data.count > byteLimit { return .unavailable("over 5 MB") }
            }
            return decode(data)
        } catch let error as URLError where error.code == .timedOut {
            return .unavailable("too slow")
        } catch let error as URLError where error.code == .notConnectedToInternet {
            return .unavailable("offline")
        } catch {
            return .unavailable("couldn’t load")
        }
    }

    static func decode(_ data: Data) -> PictureLoad {
        if VectorPicture.looksLikeSVG(data) {
            guard let image = VectorPicture.image(data, longestSide: CGFloat(shownPixels)) else { return .unavailable("couldn’t draw this SVG") }
            return .shown(image)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier),
              formats.contains(where: { type.conforms(to: $0) }) else { return .unavailable("unsupported format") }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return .unavailable("unsupported format") }
        guard width <= pixelLimit / height else { return .unavailable("too many pixels") }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: shownPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return .unavailable("couldn’t read it") }
        return .shown(UIImage(cgImage: image))
    }
}

final class PictureGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        request.url?.scheme?.lowercased() == "https" ? request : nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? (.performDefaultHandling, nil) : (.cancelAuthenticationChallenge, nil)
    }
}

/// The agent's picture, fitted whole and sitting straight on the page: no frame, no well, no badge.
/// Its provenance is a plain "Image · From the agent" row in the details; tapping it shows the exact link.
struct HeroPicture: View {
    let link: String
    @State private var pictures = Pictures.shared
    @State private var inspecting = false

    var body: some View {
        let load = pictures.loads[link] ?? .loading
        Button { inspecting = true } label: {
            ZStack {
                switch load {
                case .loading:
                    ProgressView().tint(Ink.tertiary)
                case .shown(let image):
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: image.hasAlpha ? 0 : Radius.picture, style: .continuous))
                        .padding(.horizontal, image.hasAlpha ? Space.xl : 0)
                        .transition(.opacity)
                case .unavailable(let why):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No preview").type(.callout).foregroundStyle(Ink.secondary)
                        Text(why).type(.caption).foregroundStyle(Ink.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: load.unavailable ? nil : 240)
            .contentShape(Rectangle())
            .animation(Motion.gentle, value: load.shown)
        }
        .buttonStyle(PressableStyle())
        .onAppear { pictures.load(link) }
        .accessibilityLabel(accessibility(load))
        .accessibilityHint("Shows the picture’s link")
        .sheet(isPresented: $inspecting) { PictureInspector(link: link) }
    }

    private func accessibility(_ load: PictureLoad) -> String {
        switch load {
        case .loading: return "Image from the agent, loading"
        case .shown: return "Image from the agent, not verified"
        case .unavailable(let why): return "Image from the agent can’t be shown, \(why)"
        }
    }
}

struct PictureThumb: View {
    let link: String
    var size: CGFloat = 44
    @State private var pictures = Pictures.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            switch pictures.loads[link] ?? .loading {
            case .loading:
                Color.clear
            case .shown(let image):
                if image.hasAlpha {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit().padding(size * 0.1)
                } else {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFill().frame(width: size, height: size)
                }
            case .unavailable:
                Text("No preview").type(.caption).foregroundStyle(Ink.tertiary).multilineTextAlignment(.center).minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 0.75))
        .onAppear { pictures.load(link) }
        .accessibilityHidden(true)
    }
}

struct PictureInspector: View {
    let link: String
    @Environment(\.dismiss) private var dismiss
    @State private var pictures = Pictures.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Group {
                        switch pictures.loads[link] ?? .loading {
                        case .shown(let image):
                            Image(uiImage: image).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: image.hasAlpha ? 0 : Radius.picture, style: .continuous))
                                .frame(maxHeight: 360)
                        case .loading:
                            ProgressView().frame(height: 200)
                        case .unavailable(let why):
                            Text("Can’t preview · \(why)").type(.callout).foregroundStyle(Ink.secondary).frame(height: 120)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        FieldLabel("Exact link in the request")
                        Text(Formatting.visible(link))
                            .type(.mono)
                            .foregroundStyle(Ink.primary)
                            .textSelection(.enabled)
                    }
                    Hairline()
                    Text("The agent sent this link. You sign the link, not the picture: BOGO didn’t check what it shows, and it can change after you approve.")
                        .type(.callout)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.gutter)
            }
            .canvas()
            .navigationTitle("Image from the agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

extension PictureLoad {
    var shown: Bool {
        if case .shown = self { return true }
        return false
    }

    var unavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

extension UIImage {
    var hasAlpha: Bool {
        switch cgImage?.alphaInfo {
        case .first?, .last?, .premultipliedFirst?, .premultipliedLast?: return true
        default: return false
        }
    }
}
