import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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

        // Mapbox Access Token (read from local.properties or CI environment)
        val mapboxToken = System.getenv("MAPBOX_ACCESS_TOKEN")
            ?: (rootProject.file("local.properties").takeIf { it.exists() }
                ?.let { java.util.Properties().also { p -> p.load(it.inputStream()) }["MAPBOX_ACCESS_TOKEN"] as? String })
            ?: ""
        manifestPlaceholders["MAPBOX_ACCESS_TOKEN"] = mapboxToken
    }

    signingConfigs {
        create("release") {
            if (System.getenv("CM_KEYSTORE_PATH") != null) {
                storeFile = file(System.getenv("CM_KEYSTORE_PATH"))
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD")
            } else if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("CM_KEYSTORE_PATH") != null || keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Desugaring para suportar APIs Java 8+ em versões antigas do Android
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // Edge-to-edge support for Android 15+
    implementation("androidx.activity:activity-ktx:1.9.3")
}

// Workaround: Copy APK and AAB to expected Flutter location
afterEvaluate {
    tasks.register<Copy>("copyApkToFlutterLocation") {
        from("${layout.buildDirectory.get()}/outputs/flutter-apk")
        into("${project.rootDir}/../build/app/outputs/flutter-apk")
        include("*.apk")
    }

    tasks.register<Copy>("copyAabToFlutterLocation") {
        from("${layout.buildDirectory.get()}/outputs/bundle")
        into("${project.rootDir}/../build/app/outputs/bundle")
        include("**/*.aab")
    }

    tasks.named("assembleDebug") {
        finalizedBy("copyApkToFlutterLocation")
    }

    tasks.named("assembleRelease") {
        finalizedBy("copyApkToFlutterLocation")
    }

    tasks.named("bundleDebug") {
        finalizedBy("copyAabToFlutterLocation")
    }

    tasks.named("bundleRelease") {
        finalizedBy("copyAabToFlutterLocation")
    }
}
