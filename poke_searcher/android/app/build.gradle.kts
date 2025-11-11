plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.merendandum.poke_searcher"
    compileSdk = 36  // Requerido por plugins modernos (path_provider, shared_preferences, sqlite3)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.merendandum.poke_searcher"
        // minSdk 21 requerido por NDK moderno (Android 5.0+)
        // Aunque las definiciones mencionan API 15, el NDK actual requiere mínimo 21
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
        
        // Soporte para tablets y móviles
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    // Soporte para diferentes densidades de pantalla (tablets y móviles)
    splits {
        abi {
            isEnable = false
        }
    }
}

flutter {
    source = "../.."
}
