plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
}

android {
    namespace = "com.rdtech.carrodasdelicias"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        // Habilitar desugaring para suportar APIs Java 8+ em versões antigas do Android
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rdtech.carrodasdelicias"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Mapbox Access Token
        manifestPlaceholders["MAPBOX_ACCESS_TOKEN"] = "pk.eyJ1IjoicmRnNTQ3IiwiYSI6ImNtaHNmY21zdDFpbXcyanB6N2w0Y2NyeWYifQ.RAwJc13MPekGYnD6js9g2A"
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
    // Desugaring para suportar APIs Java 8+ em versões antigas do Android
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

// Workaround: Copy APK to expected Flutter location
afterEvaluate {
    tasks.register<Copy>("copyApkToFlutterLocation") {
        from("${layout.buildDirectory.get()}/outputs/flutter-apk")
        into("${project.rootDir}/../build/app/outputs/flutter-apk")
        include("*.apk")
    }

    tasks.named("assembleDebug") {
        finalizedBy("copyApkToFlutterLocation")
    }

    tasks.named("assembleRelease") {
        finalizedBy("copyApkToFlutterLocation")
    }
}
