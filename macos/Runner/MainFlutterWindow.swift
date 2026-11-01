import Cocoa
import FlutterMacOS
import ImageIO
import UniformTypeIdentifiers
import QuickLookThumbnailing

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(x: 0, y: 0, width: 1180, height: 840)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 780, height: 600)
    self.center()
    self.title = "Converto"

    RegisterGeneratedPlugins(registry: flutterViewController)
    LocalImagePreview.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}


// ImageIO reads thumbnails from disk without loading a full-resolution bitmap
// into Dart. Requests are serial and all results return on the platform thread.
private enum LocalImagePreview {
  static let queue = DispatchQueue(label: "com.debugonaut.converto.image-preview", qos: .userInitiated)

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "converto/local_preview", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard ["thumbnail", "documentThumbnail"].contains(call.method), let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let requestedPage = arguments["page"] as? Int ?? 0
      let dimension = min(1600, max(80, arguments["dimension"] as? Int ?? 800))
      if call.method == "documentThumbnail" {
        let url = URL(fileURLWithPath: path)
        let request = QLThumbnailGenerator.Request(fileAt: url,
          size: CGSize(width: dimension, height: dimension), scale: 1,
          representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
          guard let representation = representation,
                let data = NSBitmapImageRep(cgImage: representation.cgImage).representation(using: .png, properties: [:]) else {
            DispatchQueue.main.async { result(FlutterError(code: "document_preview", message: "Use a local content excerpt for this document.", details: nil)) }
            return
          }
          let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
          let value: [String: Any] = ["path": path, "kind": "document", "sizeBytes": size,
            "page": 0, "pageCount": 1, "rasterWidth": representation.cgImage.width,
            "rasterHeight": representation.cgImage.height,
            "image": FlutterStandardTypedData(bytes: data),
            "message": "First page preview. Open original for the complete document."]
          DispatchQueue.main.async { result(value) }
        }
        return
      }
      queue.async {
        autoreleasepool {
          let url = URL(fileURLWithPath: path)
          guard let source = CGImageSourceCreateWithURL(url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary) else {
            DispatchQueue.main.async { result(FlutterError(code: "image_format", message: "Cannot preview this image.", details: nil)) }
            return
          }
          let count = CGImageSourceGetCount(source)
          let icon = url.pathExtension.lowercased() == "ico"
          var page = min(max(0, requestedPage), max(0, count - 1))
          if icon {
            var bestArea = 0
            for index in 0..<count {
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
              let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
              let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
              if width * height > bestArea { bestArea = width * height; page = index }
            }
          }
          let properties = CGImageSourceCopyPropertiesAtIndex(source, page, nil) as? [CFString: Any]
          var width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
          var height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
          let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
          if (5...8).contains(orientation) { swap(&width, &height) }
          let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension,
          ]
          guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, page, options as CFDictionary) else {
            DispatchQueue.main.async { result(FlutterError(code: "image_decode", message: "Cannot decode this image.", details: nil)) }
            return
          }
          let output = NSMutableData()
          guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            DispatchQueue.main.async { result(FlutterError(code: "image_encode", message: "Cannot create thumbnail.", details: nil)) }
            return
          }
          CGImageDestinationAddImage(destination, thumbnail, nil)
          guard CGImageDestinationFinalize(destination) else {
            DispatchQueue.main.async { result(FlutterError(code: "image_encode", message: "Cannot finish thumbnail.", details: nil)) }
            return
          }
          let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
          let data: [String: Any] = ["path": path, "kind": "image", "sizeBytes": size,
            "page": requestedPage, "pageCount": icon ? 1 : count,
            "width": width, "height": height, "rasterWidth": thumbnail.width,
            "rasterHeight": thumbnail.height, "image": FlutterStandardTypedData(bytes: output as Data)]
          DispatchQueue.main.async { result(data) }
        }
      }
    }
  }
}
