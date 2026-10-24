plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.currentsuspect.tunes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        // The key every installed Tunes was signed with. It is not in the
        // repo: CI writes it from the TUNES_KEYSTORE secret and a dev box keeps
        // its own copy here (gitignored). Without it the build falls back to
        // Android's stock debug key, which installs fresh but never as an
        // update over a phone's Tunes.
        val tunesKey = file("tunes-debug.keystore")
        if (tunesKey.exists()) {
            getByName("debug") {
                storeFile = tunesKey
                storePassword = "android"
                keyAlias = "tunes-debug"
                keyPassword = "android"
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.currentsuspect.tunes"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

    // `--target-platform android-arm64` only bounds what Flutter itself
    // compiles -- libflutter.so and libapp.so, which it does correctly. Plugin
    // libraries never pass through that step: they ship prebuilt inside AARs,
    // so mpv, sqlite3, dartjni and the media_kit helper were still packaged for
    // x86_64 and armeabi-v7a. 16.5 MB no device this installs on can load.
    //
    // `ndk.abiFilters` on the release build type was tried first and changed
    // nothing -- build 268 came out byte-identical in size to 267. AGP merges
    // abiFilters across defaultConfig and the build type as a union, so adding
    // one ABI there cannot subtract the others. Excluding by path at packaging
    // time is not subject to that merge and does not depend on evaluation
    // order.
    //
    // The cost: a debug build for an x86_64 emulator loses its native libs too.
    // Nothing here is built locally -- Flutter is not installed on the box that
    // develops this -- so that trade is currently free. Scope this per-variant
    // if that changes.
    packaging {
        jniLibs {
            excludes += listOf(
                "lib/x86/**",
                "lib/x86_64/**",
                "lib/armeabi-v7a/**",
            )
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
