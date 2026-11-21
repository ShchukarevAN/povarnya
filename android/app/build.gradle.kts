plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun androidVersionCode(version: String): Int {
    val component = "(0|[1-9]\\d{0,2})"
    val match = Regex("^$component\\.$component\\.$component$").matchEntire(version)
        ?: error("Version must have the strict form x.y.z: $version")
    val code = match.groupValues[1].toInt() * 1_000_000 +
        match.groupValues[2].toInt() * 1000 +
        match.groupValues[3].toInt()
    require(code > 0) { "Version 0.0.0 is not valid for Android" }
    return code
}

android {
    namespace = "ru.shchukarevan.povarnya"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ru.shchukarevan.povarnya"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode is an internal Android field, not part of the public
        // x.y.z version. Keep this formula in sync with update_service.dart.
        versionCode = androidVersionCode(flutter.versionName)
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_shared"
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Build Hunspell into the APK for the Dart FFI spell-check service.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
}
