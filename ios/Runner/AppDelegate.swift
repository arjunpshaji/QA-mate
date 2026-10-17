import Flutter
import UIKit
import ReplayKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.example.qa_mate/screen_recorder"
  private var currentOutputPath: String?
  private var isRecording = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let messenger = controller?.binaryMessenger {
      setupMethodChannel(messenger: messenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func setupMethodChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "isSupported":
        let supported = RPScreenRecorder.shared().isAvailable
        result(supported)
      case "startRecording":
        guard let args = call.arguments as? [String: Any],
              let outputPath = args["outputPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "outputPath is required", details: nil))
          return
        }
        self.startRecording(outputPath: outputPath, result: result)
      case "stopRecording":
        self.stopRecording(result: result)
      case "openSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
          result(true)
        } else {
          result(false)
        }
      case "generateThumbnail":
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String,
              let outputPath = args["outputPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "videoPath and outputPath required", details: nil))
          return
        }
        self.generateThumbnail(videoPath: videoPath, outputPath: outputPath, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startRecording(outputPath: String, result: @escaping FlutterResult) {
    let sharedRecorder = RPScreenRecorder.shared()
    guard sharedRecorder.isAvailable else {
      result(FlutterError(code: "RECORDER_UNAVAILABLE", message: "RPScreenRecorder is currently unavailable", details: nil))
      return
    }

    self.currentOutputPath = outputPath
    let outputURL = URL(fileURLWithPath: outputPath)
    try? FileManager.default.removeItem(at: outputURL)

    if #available(iOS 14.0, *) {
      sharedRecorder.startRecording { error in
        if let error = error {
          result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
        } else {
          self.isRecording = true
          result(true)
        }
      }
    } else {
      result(FlutterError(code: "UNSUPPORTED_VERSION", message: "iOS 14+ required for in-app screen recording", details: nil))
    }
  }

  private func stopRecording(result: @escaping FlutterResult) {
    let sharedRecorder = RPScreenRecorder.shared()
    guard isRecording else {
      result(currentOutputPath)
      return
    }

    let path = currentOutputPath
    let outputURL = path != nil ? URL(fileURLWithPath: path!) : nil

    if #available(iOS 14.0, *) {
      if let url = outputURL {
        sharedRecorder.stopRecording(withOutput: url) { error in
          self.isRecording = false
          self.currentOutputPath = nil
          if let error = error {
            result(FlutterError(code: "STOP_FAILED", message: error.localizedDescription, details: nil))
          } else {
            result(url.path)
          }
        }
      } else {
        sharedRecorder.stopRecording { _, error in
          self.isRecording = false
          self.currentOutputPath = nil
          if let error = error {
            result(FlutterError(code: "STOP_FAILED", message: error.localizedDescription, details: nil))
          } else {
            result(path)
          }
        }
      }
    } else {
      self.isRecording = false
      result(path)
    }
  }

  private func generateThumbnail(videoPath: String, outputPath: String, result: @escaping FlutterResult) {
    let videoURL = URL(fileURLWithPath: videoPath)
    let asset = AVAsset(url: videoURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    let time = CMTime(seconds: 0, preferredTimescale: 60)

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let uiImage = UIImage(cgImage: cgImage)
        if let data = uiImage.jpegData(compressionQuality: 0.85) {
          try data.write(to: URL(fileURLWithPath: outputPath))
          DispatchQueue.main.async { result(outputPath) }
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "ENCODE_FAILED", message: "Failed to encode JPEG", details: nil))
          }
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "THUMBNAIL_ERROR", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
