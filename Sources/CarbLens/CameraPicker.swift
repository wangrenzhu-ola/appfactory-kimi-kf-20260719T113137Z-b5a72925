import SwiftUI
#if canImport(UIKit)
import UIKit
import AVFoundation
#endif

#if canImport(UIKit)
/// iOS 14-compatible camera / library picker wrapped for SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    enum Source {
        case camera
        case library

        var pickerSource: UIImagePickerController.SourceType {
            switch self {
            case .camera: return .camera
            case .library: return .photoLibrary
            }
        }
    }

    let source: Source
    let onImage: (Data) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source.pickerSource
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onImage(data)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

enum CameraPermission {
    static var isGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static var isDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    static func request(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
}
#endif
