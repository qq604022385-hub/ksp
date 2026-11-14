import UIKit
import Flutter
import AVKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        let auth = FlutterMethodChannel(name: "local.kanke/device_auth", binaryMessenger: engineBridge.applicationRegistrar.messenger())
        auth.setMethodCallHandler { call, result in
            do {
                let tag = Data("local.kanke.device.p256.v1".utf8)
                let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag,
                    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom, kSecReturnRef as String: true]
                var existing: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &existing)
                let key: SecKey
                if status == errSecSuccess, let existing = existing {
                    key = existing as! SecKey
                } else if status == errSecItemNotFound {
                    var error: Unmanaged<CFError>?
                    let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                        kSecAttrKeySizeInBits as String: 256, kSecPrivateKeyAttrs as String: [
                            kSecAttrIsPermanent as String: true, kSecAttrApplicationTag as String: tag,
                            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]]
                    guard let created = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
                        throw error!.takeRetainedValue() as Error
                    }
                    key = created
                } else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
                switch call.method {
                case "publicKey":
                    guard let publicKey = SecKeyCopyPublicKey(key), let bytes = SecKeyCopyExternalRepresentation(publicKey, nil) else {
                        throw NSError(domain: "KankeAuth", code: 1)
                    }
                    result((bytes as Data).base64EncodedString())
                case "sign":
                    guard let value = call.arguments as? String else { throw NSError(domain: "KankeAuth", code: 2) }
                    var error: Unmanaged<CFError>?
                    guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, Data(value.utf8) as CFData, &error) else {
                        throw error!.takeRetainedValue() as Error
                    }
                    result((signature as Data).base64EncodedString())
                case "readRefresh", "writeRefresh":
                    let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: "local.kanke.device_auth", kSecAttrAccount as String: "refresh.v1"]
                    if call.method == "readRefresh" {
                        var data: CFTypeRef?
                        let code = SecItemCopyMatching(item.merging([kSecReturnData as String: true]) { _, b in b } as CFDictionary, &data)
                        if code == errSecItemNotFound { result("") }
                        else if code == errSecSuccess, let bytes = data as? Data { result(String(data: bytes, encoding: .utf8) ?? "") }
                        else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
                    } else {
                        let value = Data(((call.arguments as? String) ?? "").utf8)
                        let update = SecItemUpdate(item as CFDictionary, [kSecValueData as String: value] as CFDictionary)
                        if update == errSecItemNotFound {
                            let add = SecItemAdd(item.merging([kSecValueData as String: value,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, b in b } as CFDictionary, nil)
                            if add != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(add)) }
                        } else if update != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(update)) }
                        result(nil)
                    }
                default: result(FlutterMethodNotImplemented)
                }
            } catch { result(FlutterError(code: "device_key_error", message: "设备安全存储不可用", details: nil)) }
        }

        let channel = FlutterMethodChannel(
            name: "com.predidit.kazumi/intent",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "openWithReferer" {
                guard let args = call.arguments else { return }
                if let myArgs = args as? [String: Any],
                   let url = myArgs["url"] as? String,
                   let referer = myArgs["referer"] as? String {
                    self?.openVideoWithReferer(url: url, referer: referer)
                }
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        let storageChannel = FlutterMethodChannel(
            name: "com.predidit.kazumi/storage",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        storageChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "getAvailableStorage" {
                do {
                    let attrs = try FileManager.default.attributesOfFileSystem(
                        forPath: NSHomeDirectory()
                    )
                    if let freeSize = attrs[.systemFreeSize] as? Int64 {
                        result(freeSize)
                    } else {
                        result(-1)
                    }
                } catch {
                    result(-1)
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    // TODO: ADD VLC SUPPORT
    // VLC can be downloaded from iOS App Store, but don't know how to build selectable app lists, while checking if it is installled.
    // VLC supports more video formats than AVPlayer but does not support referer while AVPlayer does
    private func openVideoWithReferer(url: String, referer: String) {
        guard let videoUrl = URL(string: url) else { return }

        let headers: [String: String] = [
            "Referer": referer,
        ]
        let asset = AVURLAsset(url: videoUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        playerViewController.videoGravity = AVLayerVideoGravity.resizeAspect

        // Use UIScene API instead of deprecated keyWindow
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        rootViewController.present(playerViewController, animated: true) {
            playerViewController.player?.play()
        }

//        guard let appURL = URL(string: "vlc-x-callback://x-callback-url/stream?url=" + url) else {
//            return
//        }
//        if UIApplication.shared.canOpenURL(appURL) && referer.isEmpty {
//            UIApplication.shared.open(appURL, options: [:], completionHandler: nil)
//        }
    }
}
