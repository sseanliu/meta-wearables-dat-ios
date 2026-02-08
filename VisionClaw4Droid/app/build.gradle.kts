import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.dagger.hilt.android")
    kotlin("kapt")
}

// Load local.properties for API keys
val localProps = Properties().apply {
    val localFile = rootProject.file("local.properties")
    if (localFile.exists()) load(localFile.inputStream())
}

android {
    namespace = "com.visionclaw.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.visionclaw.android"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "0.4.0"

        // Inject secrets via BuildConfig
        buildConfigField("String", "GEMINI_API_KEY",
            "\"${localProps.getProperty("GEMINI_API_KEY", "YOUR_GEMINI_API_KEY")}\"")
        buildConfigField("String", "OPENCLAW_HOST",
            "\"${localProps.getProperty("OPENCLAW_HOST", "http://YOUR_HOST.local")}\"")
        buildConfigField("int", "OPENCLAW_PORT",
            localProps.getProperty("OPENCLAW_PORT", "18789"))
        buildConfigField("String", "OPENCLAW_HOOK_TOKEN",
            "\"${localProps.getProperty("OPENCLAW_HOOK_TOKEN", "YOUR_OPENCLAW_HOOK_TOKEN")}\"")
        buildConfigField("String", "OPENCLAW_GATEWAY_TOKEN",
            "\"${localProps.getProperty("OPENCLAW_GATEWAY_TOKEN", "YOUR_OPENCLAW_GATEWAY_TOKEN")}\"")
        buildConfigField("String", "META_DAT_APP_ID",
            "\"${localProps.getProperty("META_DAT_APP_ID", "YOUR_META_APP_ID")}\"")

        // Manifest placeholders for DAT SDK
        manifestPlaceholders["META_DAT_APP_ID"] =
            localProps.getProperty("META_DAT_APP_ID", "YOUR_META_APP_ID")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    // Compose BOM
    val composeBom = platform("androidx.compose:compose-bom:2026.01.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Core Android
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")

    // Lifecycle + ViewModel
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.8.5")

    // Hilt DI
    implementation("com.google.dagger:hilt-android:2.51.1")
    kapt("com.google.dagger:hilt-compiler:2.51.1")
    implementation("androidx.hilt:hilt-navigation-compose:1.2.0")

    // Networking (OkHttp for WebSocket + HTTP)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // JSON serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // CameraX
    implementation("androidx.camera:camera-camera2:1.4.1")
    implementation("androidx.camera:camera-lifecycle:1.4.1")
    implementation("androidx.camera:camera-view:1.4.1")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // Meta Wearables DAT SDK
    implementation("com.meta.wearable:mwdat-core:0.4.0")
    implementation("com.meta.wearable:mwdat-camera:0.4.0")

    // Accompanist permissions
    implementation("com.google.accompanist:accompanist-permissions:0.36.0")

    // Unit tests (JVM — no emulator needed)
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}

kapt {
    correctErrorTypes = true
}
