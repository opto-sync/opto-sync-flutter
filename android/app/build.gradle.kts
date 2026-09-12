import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val optoSyncReleaseTaskRequested = gradle.startParameter.taskNames.any { requestedTask ->
    val taskName = requestedTask.substringAfterLast(':').lowercase()
    taskName == "build" || taskName == "assemble" || taskName == "bundle" || taskName.endsWith("release")
}

val optoSyncReleaseStorePath = System.getenv("OPTO_SYNC_ANDROID_KEYSTORE_PATH")
val optoSyncReleaseStorePassword = System.getenv("OPTO_SYNC_ANDROID_KEYSTORE_PASSWORD")
val optoSyncReleaseKeyAlias = System.getenv("OPTO_SYNC_ANDROID_KEY_ALIAS")
val optoSyncReleaseKeyPassword = System.getenv("OPTO_SYNC_ANDROID_KEY_PASSWORD")
val optoSyncReleaseCertificateSha256 = System.getenv("OPTO_SYNC_ANDROID_CERT_SHA256")

fun normalizeCertificateFingerprint(value: String): String =
    value.filterNot { it.isWhitespace() || it == ':' || it == '-' }.uppercase()

fun certificateSha256(certificate: X509Certificate): String =
    MessageDigest.getInstance("SHA-256").digest(certificate.encoded).joinToString("") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0').uppercase()
    }

fun loadOptoSyncReleaseKeyStore(storeFile: File, password: CharArray): KeyStore {
    for (storeType in listOf(KeyStore.getDefaultType(), "JKS", "PKCS12").distinct()) {
        try {
            return KeyStore.getInstance(storeType).apply {
                storeFile.inputStream().use { input -> load(input, password) }
            }
        } catch (_: Exception) {
            // Try the next Android-compatible format without exposing credentials.
        }
    }
    throw GradleException(
        "Opto Sync Android release signing is unavailable: the keystore cannot be opened with the configured credentials.",
    )
}

fun validateOptoSyncReleaseSigning(): File {
    val missing = buildList {
        if (optoSyncReleaseStorePath.isNullOrBlank()) add("OPTO_SYNC_ANDROID_KEYSTORE_PATH")
        if (optoSyncReleaseStorePassword.isNullOrBlank()) add("OPTO_SYNC_ANDROID_KEYSTORE_PASSWORD")
        if (optoSyncReleaseKeyAlias.isNullOrBlank()) add("OPTO_SYNC_ANDROID_KEY_ALIAS")
        if (optoSyncReleaseKeyPassword.isNullOrBlank()) add("OPTO_SYNC_ANDROID_KEY_PASSWORD")
        if (optoSyncReleaseCertificateSha256.isNullOrBlank()) add("OPTO_SYNC_ANDROID_CERT_SHA256")
    }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "Opto Sync Android release signing is unavailable: missing protected signing inputs: ${missing.joinToString(", ")}",
        )
    }

    val storeFile = rootProject.file(optoSyncReleaseStorePath!!.trim()).canonicalFile
    if (!storeFile.isFile) {
        throw GradleException("Opto Sync Android release signing is unavailable: the configured keystore is not a regular file.")
    }
    val defaultDebugStore = File(System.getProperty("user.home") ?: "", ".android/debug.keystore").canonicalFile
    if (storeFile == defaultDebugStore) {
        throw GradleException("Opto Sync Android release signing refuses the default Android debug keystore.")
    }

    val alias = optoSyncReleaseKeyAlias!!.trim()
    if (alias.equals("androiddebugkey", ignoreCase = true)) {
        throw GradleException("Opto Sync Android release signing refuses the Android debug key alias.")
    }
    val keyStore = loadOptoSyncReleaseKeyStore(storeFile, optoSyncReleaseStorePassword!!.toCharArray())
    if (!keyStore.containsAlias(alias) || !keyStore.isKeyEntry(alias)) {
        throw GradleException("Opto Sync Android release signing is unavailable: the configured alias is not a private-key entry.")
    }
    try {
        keyStore.getKey(alias, optoSyncReleaseKeyPassword!!.toCharArray())
            ?: throw GradleException("Opto Sync Android release signing is unavailable: the configured private key is missing.")
    } catch (error: GradleException) {
        throw error
    } catch (_: Exception) {
        throw GradleException("Opto Sync Android release signing is unavailable: the private key cannot be opened with the configured credentials.")
    }

    val certificate = keyStore.getCertificate(alias) as? X509Certificate
        ?: throw GradleException("Opto Sync Android release signing is unavailable: the configured alias has no X.509 certificate.")
    val debugSubject = Regex("(?:^|,)\\s*CN=Android Debug\\s*(?:,|$)", RegexOption.IGNORE_CASE)
    if (debugSubject.containsMatchIn(certificate.subjectX500Principal.name)) {
        throw GradleException("Opto Sync Android release signing refuses an Android debug certificate.")
    }
    val expectedFingerprint = normalizeCertificateFingerprint(optoSyncReleaseCertificateSha256!!)
    if (!Regex("^[0-9A-F]{64}$").matches(expectedFingerprint)) {
        throw GradleException("Opto Sync Android release signing is unavailable: OPTO_SYNC_ANDROID_CERT_SHA256 must be 64 hexadecimal digits.")
    }
    if (certificateSha256(certificate) != expectedFingerprint) {
        throw GradleException("Opto Sync Android release signing is unavailable: the certificate fingerprint does not match the approved key.")
    }
    return storeFile
}

val optoSyncReleaseInputsComplete = listOf(
    optoSyncReleaseStorePath,
    optoSyncReleaseStorePassword,
    optoSyncReleaseKeyAlias,
    optoSyncReleaseKeyPassword,
    optoSyncReleaseCertificateSha256,
).all { !it.isNullOrBlank() }

val configuredOptoSyncReleaseStore = when {
    optoSyncReleaseTaskRequested -> validateOptoSyncReleaseSigning()
    optoSyncReleaseInputsComplete -> rootProject.file(optoSyncReleaseStorePath!!.trim())
    else -> null
}

android {
    namespace = "dev.codexsweep.opto_sync_opto_sync_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.codexsweep.opto_sync_opto_sync_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val optoSyncReleaseSigningConfig = configuredOptoSyncReleaseStore?.let { store ->
        signingConfigs.create("release") {
            storeFile = store
            storePassword = optoSyncReleaseStorePassword!!
            keyAlias = optoSyncReleaseKeyAlias!!.trim()
            keyPassword = optoSyncReleaseKeyPassword!!
        }
    }

    buildTypes {
        release {
            signingConfig = optoSyncReleaseSigningConfig
        }
    }
}

val verifyOptoSyncAndroidReleaseSigning = tasks.register("verifyOptoSyncAndroidReleaseSigning") {
    group = "verification"
    description = "Fails closed unless the approved Opto Sync Android release key is available and valid."
    doLast {
        validateOptoSyncReleaseSigning()
    }
}

afterEvaluate {
    tasks.matching { task ->
        val taskName = task.name.lowercase()
        taskName.contains("release") &&
            listOf("assemble", "bundle", "package", "sign", "validate").any(taskName::startsWith)
    }.configureEach {
        dependsOn(verifyOptoSyncAndroidReleaseSigning)
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
