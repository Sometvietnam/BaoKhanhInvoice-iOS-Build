import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct QRCodeImage: View {
    let text: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = makeQRCode(from: text ?? "") {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [6]))
                    Text("QR")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func makeQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
