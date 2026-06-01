plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aiscan.ai_scan"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aiscan.ai_scan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // TFLite Select TF Ops：模型使用了 FlexDepthwiseConv2dNative 等 TF 原生算子
    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.16.1")

    // ============================================================
    // CameraX（Android 相机框架）
    //
    // 核心组件：
    // - ProcessCameraProvider: 相机生命周期管理
    // - ImageAnalysis: 逐帧数据分析
    // - CameraSelector: 前/后置摄像头选择
    // - camera-lifecycle: 绑定 LifecycleOwner
    // - camera-view: 预览用例（本项目仅用 ImageAnalysis）
    //
    // 版本选择：1.3.x 稳定版，兼容 Android 5.0+ (minSdk 21)
    // ============================================================
    val cameraxVersion = "1.3.4"
    implementation("androidx.camera:camera-core:${cameraxVersion}")
    implementation("androidx.camera:camera-camera2:${cameraxVersion}")
    implementation("androidx.camera:camera-lifecycle:${cameraxVersion}")
    implementation("androidx.camera:camera-view:${cameraxVersion}")

    // Guava ListenableFuture（CameraX 的 ProcessCameraProvider.getInstance() 返回值）
    // CameraX 传递依赖可能被 Gradle 排除，需显式声明
    implementation("com.google.guava:guava:33.0.0-android")

    // ============================================================
    // ML Kit 人脸检测
    //
    // 端侧实时人脸检测，返回人脸边界框，
    // 通过 Google Play Services 按需下载模型，无需打包。
    // ============================================================
    implementation("com.google.mlkit:face-detection:16.1.6")
}
