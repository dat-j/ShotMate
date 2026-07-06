plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.shotmate.shotmate_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.shotmate.shotmate_app"
        // minSdk 24: yêu cầu của camera plugin + MediaPipe Tasks Vision (native module)
        minSdk = maxOf(24, flutter.minSdkVersion)
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

    // MediaPipe .task model là zip nén sẵn — không cho aapt nén lại (load fail nếu nén)
    androidResources {
        noCompress += "task"
    }
}

dependencies {
    // CameraX — ImageAnalysis pipeline (ADR-0001: KHÔNG dùng startImageStream)
    val cameraxVersion = "1.3.4"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")

    // MediaPipe Tasks Vision — pose_landmarker_lite (GPU delegate)
    implementation("com.google.mediapipe:tasks-vision:0.10.14")

    // ML Kit — object detection (subject fallback) + face detection
    implementation("com.google.mlkit:object-detection:17.0.2")
    implementation("com.google.mlkit:face-detection:16.1.7")
    // ML Kit — image labeling (scene classifier, spec-sprint-2 FR-S2-2)
    implementation("com.google.mlkit:image-labeling:17.0.9")
}

flutter {
    source = "../.."
}
