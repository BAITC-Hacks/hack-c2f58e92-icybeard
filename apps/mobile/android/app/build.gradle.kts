import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Подпись релиза. Источники по порядку: android/key.properties (локально, формат из документации Flutter:
// storeFile, storePassword, keyAlias, keyPassword; storeFile — относительно android/app) или переменные окружения
// ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD (CI, release.yml).
// Нет ни того, ни другого — релиз подписывается debug-ключом с предупреждением (демо-сборка, не для Google Play).
// key.properties и *.jks/*.keystore в .gitignore: ключ в репозиторий не попадает.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        FileInputStream(file).use { load(it) }
    }
}

fun signingValue(property: String, envVariable: String): String? =
    (keystoreProperties.getProperty(property) ?: System.getenv(envVariable))?.takeIf { it.isNotBlank() }

val releaseSigning = mapOf(
    "storeFile / ANDROID_KEYSTORE_PATH" to signingValue("storeFile", "ANDROID_KEYSTORE_PATH"),
    "storePassword / ANDROID_KEYSTORE_PASSWORD" to signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD"),
    "keyAlias / ANDROID_KEY_ALIAS" to signingValue("keyAlias", "ANDROID_KEY_ALIAS"),
    "keyPassword / ANDROID_KEY_PASSWORD" to signingValue("keyPassword", "ANDROID_KEY_PASSWORD"),
)
val hasReleaseSigning = releaseSigning.values.all { it != null }
val missingSigning = releaseSigning.filterValues { it == null }.keys
if (!hasReleaseSigning && missingSigning.size < releaseSigning.size) {
    // Часть параметров задана — это ошибка настройки, а не «ключа нет»: молча уходить на debug-подпись нельзя
    throw GradleException("Подпись релиза настроена не полностью, не хватает: ${missingSigning.joinToString()}")
}
val buildsRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (!hasReleaseSigning && buildsRelease) {
    // уровень QUIET: flutter build запускает Gradle с -q, и обычный warn в выводе не виден
    logger.quiet(
        "WARNING: ключ релиза не задан (android/key.properties или ANDROID_KEYSTORE_*) — " +
            "release подписывается debug-ключом: демо-сборка, не для Google Play",
    )
}

android {
    namespace = "kz.darumen.darumen"
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
        applicationId = "kz.darumen.darumen"
        // versionName и versionCode — из pubspec.yaml или --build-name/--build-number (в CI: тег и номер запуска)
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                val storePath = releaseSigning.getValue("storeFile / ANDROID_KEYSTORE_PATH")!!
                storeFile = file(storePath).also {
                    if (!it.isFile) throw GradleException("Нет файла ключа подписи: ${it.absolutePath}")
                }
                storePassword = releaseSigning.getValue("storePassword / ANDROID_KEYSTORE_PASSWORD")
                keyAlias = releaseSigning.getValue("keyAlias / ANDROID_KEY_ALIAS")
                keyPassword = releaseSigning.getValue("keyPassword / ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseSigning) "release" else "debug")
        }
    }
}

flutter {
    source = "../.."
}
