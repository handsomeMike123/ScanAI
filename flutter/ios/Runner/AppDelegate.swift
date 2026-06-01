import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    /// 相机通道处理器
    ///
    /// 【注册通道的入口】
    /// CameraChannelHandler 在此注册 MethodChannel、EventChannel 和 Texture，
    /// Flutter 引擎启动后即可通过这些通道与原生通信。
    private let cameraChannelHandler = CameraChannelHandler()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // 注册原生相机通道（含 Texture 支持）
        //
        // 【关键步骤】
        // 必须在 Flutter 引擎启动后立即注册，
        // 否则 Flutter 端调用 MethodChannel 时会找不到 Handler。
        //
        // 【v3 变更】
        // 新增 textureRegistry 参数，用于注册 GPU 纹理，
        // 实现 60fps 零拷贝相机预览。
        guard let controller = window?.rootViewController as? FlutterViewController else {
            NSLog("[AppDelegate] ❌ 无法获取 FlutterViewController")
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        // 通过 FlutterPluginRegistrar 获取 textureRegistry
        guard let registrar = controller.registrar(forPlugin: "CameraChannelHandler") else {
            NSLog("[AppDelegate] ❌ 无法获取 FlutterPluginRegistrar")
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        cameraChannelHandler.register(with: registrar.messenger(), textureRegistry: registrar.textures())
        NSLog("[AppDelegate] ✅ 原生相机通道已注册（含 Texture 支持）")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
