import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var documents: IOSDocuments?
  private var documentsChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ConvertoDocuments") else { return }
    documents = IOSDocuments { [weak registrar] in registrar?.viewController }
    let channel = FlutterMethodChannel(name: "com.converto.app/documents", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let documents = self?.documents else {
        result(FlutterError(code: "APP_CLOSED", message: "Reopen the app and try again.", details: nil))
        return
      }
      documents.handle(call, result: result)
    }
    documentsChannel = channel
  }
}

/// Only explicit imports and exports cross the app sandbox.
private final class IOSDocuments: NSObject, UIDocumentPickerDelegate,
  UIDocumentInteractionControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private let presenter: () -> UIViewController?
  private let work = DispatchQueue(label: "com.converto.app.documents", qos: .userInitiated)
  private var pending: FlutterResult?
  private var purpose: String?
  private var copying = false
  private var opener: UIDocumentInteractionController?
  private let manager = FileManager.default
  private var data: URL { manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Converto", isDirectory: true) }
  private var results: URL { manager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Results", isDirectory: true) }
  private var imports: URL { manager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("imports", isDirectory: true) }

  init(presenter: @escaping () -> UIViewController?) { self.presenter = presenter }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "storagePaths":
        for var directory in [data, results, imports] {
          try manager.createDirectory(at: directory, withIntermediateDirectories: true)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try directory.setResourceValues(values)
        }
        result(["data": data.path, "output": results.path])
      case "pickFiles":
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
        let options = call.arguments as? [String: Any]
        picker.allowsMultipleSelection = options?["allowMultiple"] as? Bool ?? true
        try present(picker, purpose: "import", result: result)
      case "releaseImport":
        guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else { throw documentError("Choose an imported file.") }
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(imports.resolvingSymlinksInPath().standardizedFileURL.path + "/") else { throw documentError("Only imported temporary copies can be removed.") }
        if manager.fileExists(atPath: file.path) {
          let values = try file.resourceValues(forKeys: [.isRegularFileKey])
          guard values.isRegularFile == true else { throw documentError("Only imported regular files can be removed.") }
          try manager.removeItem(at: file)
        }
        result(nil)
      case "exportFile":
        let file = try privateFile(call, allowImport: false)
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        try present(picker, purpose: "export", result: result)
      case "openFile":
        let file = try privateFile(call, allowImport: true)
        guard let view = currentPresenter() else { throw documentError("The file viewer is not ready. Try again.") }
        let controller = UIDocumentInteractionController(url: file)
        controller.delegate = self
        opener = controller
        if !controller.presentPreview(animated: true) && !controller.presentOpenInMenu(
          from: CGRect(x: view.view.bounds.midX, y: view.view.bounds.midY, width: 1, height: 1),
          in: view.view, animated: true) {
          throw documentError("No installed viewer can open this format. Use Export to save a copy.")
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "DOCUMENT_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func currentPresenter() -> UIViewController? {
    guard var view = presenter(), view.viewIfLoaded?.window != nil else { return nil }
    while let next = view.presentedViewController, !next.isBeingDismissed { view = next }
    return view
  }

  private func present(_ picker: UIDocumentPickerViewController, purpose: String, result: @escaping FlutterResult) throws {
    guard pending == nil else { throw documentError("Finish or cancel the open document dialog first.") }
    guard let view = currentPresenter(), view.presentedViewController == nil,
      !view.isBeingPresented, !view.isBeingDismissed else {
      throw documentError("The document picker is not ready. Try again.")
    }
    pending = result
    self.purpose = purpose
    picker.delegate = self
    view.present(picker, animated: true)
    picker.presentationController?.delegate = self
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(purpose == "import" ? nil : false) }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if !copying { finish(purpose == "import" ? nil : false) }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard pending != nil else { return }
    if purpose == "export" { finish(true); return }
    copying = true
    let batch = imports.appendingPathComponent(UUID().uuidString, isDirectory: true)
    work.async { [weak self] in
      do {
        guard !urls.isEmpty else { throw documentError("No files were selected.") }
        let manager = FileManager.default
        try manager.createDirectory(at: batch, withIntermediateDirectories: true)
        var paths = [String]()
        for (index, url) in urls.enumerated() {
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          var coordinationError: NSError?
          var copyError: Error?
          NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { source in
            do {
              let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
              guard values.isRegularFile == true && values.isSymbolicLink != true else { throw documentError("Choose regular files to import.") }
              let folder = batch.appendingPathComponent(String(index), isDirectory: true)
              try manager.createDirectory(at: folder, withIntermediateDirectories: true)
              let name = source.lastPathComponent.unicodeScalars.map {
                $0.value < 32 || $0.value == 127 || $0 == "/" || $0 == "\\" ? "_" : String($0)
              }.joined().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
              guard !name.isEmpty else { throw documentError("The file has no usable name.") }
              let destination = folder.appendingPathComponent(name)
              try manager.copyItem(at: source, to: destination)
              paths.append(destination.path)
            } catch { copyError = error }
          }
          if let error = coordinationError { throw error }
          if let error = copyError { throw error }
        }
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { try? FileManager.default.removeItem(at: batch); return }
          self.finish(paths)
        }
      } catch {
        try? FileManager.default.removeItem(at: batch)
        DispatchQueue.main.async { [weak self] in self?.finish(FlutterError(code: "DOCUMENT_ERROR", message: error.localizedDescription, details: nil)) }
      }
    }
  }

  private func privateFile(_ call: FlutterMethodCall, allowImport: Bool) throws -> URL {
    guard let values = call.arguments as? [String: Any], let path = values["path"] as? String else { throw documentError("Choose a file first.") }
    let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let inResults = file.path.hasPrefix(results.resolvingSymlinksInPath().path + "/")
    let inImports = allowImport && file.path.hasPrefix(imports.resolvingSymlinksInPath().path + "/")
    guard (inResults || inImports), try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw documentError("This file has moved or been deleted. Run the tool again.") }
    return file
  }

  private func finish(_ value: Any?) {
    let reply = pending
    pending = nil
    purpose = nil
    copying = false
    reply?(value)
  }

  func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController { presenter() ?? UIViewController() }
}

private func documentError(_ message: String) -> NSError { NSError(domain: "ConvertoDocuments", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
