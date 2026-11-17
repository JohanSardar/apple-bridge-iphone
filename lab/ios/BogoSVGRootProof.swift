import UIKit

@main
enum BogoSVGRootProof {
    static func main() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" fill="red">
          <rect width="10" height="10"/>
        </svg>
        """
        guard let image = VectorPicture.image(Data(svg.utf8), longestSide: 10)?.cgImage else {
            fatalError("Fixture must render")
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard pixel[0] > 240, pixel[1] < 10, pixel[2] < 10, pixel[3] > 240 else {
            print("FAIL S1: SVG root fill must produce red; got RGBA \(pixel)")
            exit(1)
        }
        print("PASS S1")
    }
}
