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

struct HeroPicture: View {
    let link: String
    @State private var pictures = Pictures.shared
    @State private var inspecting = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        let load = pictures.loads[link] ?? .loading
        Button { inspecting = true } label: {
            ZStack {
                Ink.well
                switch load {
                case .loading:
                    Color.clear.shimmering()
                case .shown(let image):
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(image.hasAlpha ? Space.xxl : 0)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                case .unavailable(let why):
                    VStack(spacing: Space.xs) {
                        Image(systemName: "photo")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Ink.tertiary)
                        Text("No preview").type(.label).foregroundStyle(Ink.secondary)
                        Text(why).type(.caption).foregroundStyle(Ink.tertiary)
                    }
                    .padding(Space.l)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(shape)
            .overlay(alignment: .topLeading) { AgentChip(text: "Agent’s picture").padding(Space.s) }
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
        case .loading: return "Agent’s picture, loading"
        case .shown: return "Agent’s picture, unverified"
        case .unavailable(let why): return "Agent’s picture can’t be shown, \(why)"
        }
    }
}

struct AgentChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .bold))
            Text(text).type(.caption, weight: .medium)
        }
        .foregroundStyle(Ink.primary.opacity(0.75))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

struct PictureThumb: View {
    let link: String
    var size: CGFloat = 44
    @State private var pictures = Pictures.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            Ink.well
            switch pictures.loads[link] ?? .loading {
            case .loading:
                Color.clear.shimmering()
            case .shown(let image):
                if image.hasAlpha {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit().padding(size * 0.14)
                } else {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFill().frame(width: size, height: size)
                }
            case .unavailable:
                Image(systemName: "photo").font(.system(size: size * 0.36, weight: .light)).foregroundStyle(Ink.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 0.5))
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
                            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: image.hasAlpha ? 0 : Radius.tile, style: .continuous)).padding(Space.l)
                        case .loading:
                            ProgressView().frame(height: 200)
                        case .unavailable(let why):
                            VStack(spacing: Space.xs) {
                                Image(systemName: "photo").font(.system(size: 30, weight: .light)).foregroundStyle(Ink.tertiary)
                                Text("Can’t preview · \(why)").type(.label).foregroundStyle(Ink.secondary)
                            }
                            .frame(height: 200)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Ink.well, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("Exact link in the request")
                        Text(Formatting.visible(link))
                            .type(.mono)
                            .foregroundStyle(Ink.primary)
                            .textSelection(.enabled)
                            .card(padding: Space.m, radius: Radius.inner)
                    }
                    Label {
                        Text("The agent sent this link. You sign the link, not the picture: BOGO didn’t check what it shows, and it can change after you approve.")
                            .type(.callout)
                            .foregroundStyle(Ink.secondary)
                    } icon: {
                        Image(systemName: "sparkle").foregroundStyle(Ink.claim)
                    }
                }
                .padding(Space.gutter)
            }
            .canvas()
            .navigationTitle("Agent’s picture")
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
}

extension UIImage {
    var hasAlpha: Bool {
        switch cgImage?.alphaInfo {
        case .first?, .last?, .premultipliedFirst?, .premultipliedLast?: return true
        default: return false
        }
    }
}
