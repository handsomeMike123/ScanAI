//
//  SceneDelegate.swift
//  coreML_iOS_test
//
//  修改：设置 TabBarController 作为根视图
//  两个 Tab：心情检测 + 图像分类
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // 创建 TabBarController
        let tabBarController = UITabBarController()
        
        // Tab 1: 心情检测
        let moodVC = MoodDetectionViewController()
        moodVC.tabBarItem = UITabBarItem(
            title: "心情检测",
            image: UIImage(systemName: "face.smiling"),
            selectedImage: UIImage(systemName: "face.smiling.fill")
        )
        
        // Tab 2: 实时心情
        let realtimeVC = RealTimeMoodViewController()
        realtimeVC.tabBarItem = UITabBarItem(
            title: "实时心情",
            image: UIImage(systemName: "video.circle"),
            selectedImage: UIImage(systemName: "video.circle.fill")
        )
        
        // Tab 3: 图像分类
        let classifyVC = ImageClassificationViewController()
        classifyVC.tabBarItem = UITabBarItem(
            title: "图像分类",
            image: UIImage(systemName: "photo.on.rectangle"),
            selectedImage: UIImage(systemName: "photo.fill.on.rectangle.fill")
        )
        
        // 包装在 NavigationController 中
        tabBarController.viewControllers = [
            UINavigationController(rootViewController: moodVC),
            UINavigationController(rootViewController: realtimeVC),
            UINavigationController(rootViewController: classifyVC)
        ]
        
        // 设置 Window
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
