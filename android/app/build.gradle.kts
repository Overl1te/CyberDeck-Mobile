plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyStoreFile: String? =
    System.getenv("CYBERDECK_UPLOAD_STORE_FILE")
        ?: (project.findProperty("CYBERDECK_UPLOAD_STORE_FILE") as String?)
val releaseKeyStorePassword: String? =
    System.getenv("CYBERDECK_UPLOAD_STORE_PASSWORD")
        ?: (project.findProperty("CYBERDECK_UPLOAD_STORE_PASSWORD") as String?)
val releaseKeyAlias: String? =
    System.getenv("CYBERDECK_UPLOAD_KEY_ALIAS")
        ?: (project.findProperty("CYBERDECK_UPLOAD_KEY_ALIAS") as String?)
val releaseKeyPassword: String? =
    System.getenv("CYBERDECK_UPLOAD_KEY_PASSWORD")
        ?: (project.findProperty("CYBERDECK_UPLOAD_KEY_PASSWORD") as String?)

android {
    namespace = "com.overl1te.cyberdeckmobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            if (
                !releaseKeyStoreFile.isNullOrBlank() &&
                !releaseKeyStorePassword.isNullOrBlank() &&
                !releaseKeyAlias.isNullOrBlank() &&
                !releaseKeyPassword.isNullOrBlank()
            ) {
                storeFile = file(releaseKeyStoreFile)
                storePassword = releaseKeyStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.overl1te.cyberdeckmobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Uses release keystore from env/properties when provided.
            // Falls back to debug key for local smoke builds.
            val releaseConfig = signingConfigs.findByName("release")
            signingConfig = if (releaseConfig != null && releaseConfig.storeFile != null) {
                releaseConfig
            } else {
                signingConfigs.getByName("debug")
            }
        }

        debug {

        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
