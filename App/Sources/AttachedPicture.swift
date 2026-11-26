import SwiftUI
import UIKit

/// A picture the author attaches for the companion to see (Kevin, 2026-11-26: "do pictures"),
/// from Photos or the camera: kept as a JPEG with the world's conversations
/// (`Companion.keepPicture`), no larger than the model looks at.
enum AttachedPicture {
    /// The longer side, in pixels: past what the model's eyes take in (they make at most 280
    /// tokens of a picture), and small enough to keep many.
    private static let longerSide: CGFloat = 1536

    /// `image` as the JPEG kept, scaled down if it's larger.
    static func jpeg(_ image: UIImage) -> Data? {
        let size = image.size
        let scale = min(1, longerSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))   // upright, whatever the camera's orientation
        }
        return drawn.jpegData(compressionQuality: 0.85)
    }
}

/// A picture attached to a message, small, as Messages shows one before it opens.
struct PictureThumbnail: View {
    var url: URL?
    var height: CGFloat = 120

    var body: some View {
        if let url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: height)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel("Picture")
        } else {
            Label("Picture", systemImage: "photo")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// iOS's own camera, for a photo to attach (nil when cancelled).
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor final class Coordinator: NSObject, @MainActor UIImagePickerControllerDelegate,
                                        @MainActor UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
