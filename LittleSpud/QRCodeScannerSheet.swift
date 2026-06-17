import SwiftUI

struct QRCodeScannerSheet: UIViewControllerRepresentable {
    var onResult: (QRCodeScanResult) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let controller = QRCodeScannerViewController()
        controller.onResult = onResult
        return controller
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}
