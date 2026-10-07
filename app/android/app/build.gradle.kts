import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Private signing settings are local to the build machine and ignored by Git.
val releaseKeys = Properties()
val releaseKeysFile = rootProject.file("key.properties")
if (releaseKeysFile.isFile) {
    releaseKeysFile.inputStream().use { releaseKeys.load(it) }
}

android {
    namespace = "com.jemcalc.jem_calc"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jemcalc.jem_calc"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
            storeFile = releaseKeys.getProperty("storeFile")?.let { file(it) }
            storePassword = releaseKeys.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Never silently distribute an unsigned APK or one signed with debug keys.
tasks.matching { it.name == "validateSigningRelease" }.configureEach {
    doFirst {
        val requiredKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        check(requiredKeys.all { !releaseKeys.getProperty(it).isNullOrBlank() }) {
            "Configure the private android/key.properties before building a release. See README.md."
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
