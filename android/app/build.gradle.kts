plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val releaseSigningValues = mapOf(
    "storeFile" to System.getenv("ANDROID_SIGNING_STORE_FILE").orEmpty(),
    "storePassword" to System.getenv("ANDROID_SIGNING_STORE_PASSWORD").orEmpty(),
    "keyAlias" to System.getenv("ANDROID_SIGNING_KEY_ALIAS").orEmpty(),
    "keyPassword" to System.getenv("ANDROID_SIGNING_KEY_PASSWORD").orEmpty(),
)
val suppliedReleaseSigningValues = releaseSigningValues.filterValues { it.isNotBlank() }
if (suppliedReleaseSigningValues.isNotEmpty() && suppliedReleaseSigningValues.size != releaseSigningValues.size) {
    throw GradleException("Android release signing requires store file, store password, key alias, and key password.")
}

android {
    namespace = "com.tatertotterson.littlespud.android"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.tatertotterson.littlespud.android"
        minSdk = 26
        targetSdk = 37
        versionCode = System.getenv("LITTLE_SPUD_VERSION_CODE")?.toIntOrNull()?.takeIf { it > 0 } ?: 2
        versionName = System.getenv("LITTLE_SPUD_VERSION_NAME")?.trim()?.ifBlank { null } ?: "1.3.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
        buildConfigField(
            "boolean",
            "FIREBASE_CONFIGURED",
            file("google-services.json").exists().toString(),
        )
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    signingConfigs {
        if (suppliedReleaseSigningValues.size == releaseSigningValues.size) {
            create("release") {
                storeFile = file(releaseSigningValues.getValue("storeFile"))
                storePassword = releaseSigningValues.getValue("storePassword")
                keyAlias = releaseSigningValues.getValue("keyAlias")
                keyPassword = releaseSigningValues.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.06.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.core:core-ktx:1.17.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
    implementation("com.squareup.okhttp3:okhttp:5.1.0")
    implementation("io.coil-kt.coil3:coil-compose:3.3.0")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.3.0")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-session:1.8.0")

    implementation(platform("com.google.firebase:firebase-bom:34.17.0"))
    implementation("com.google.firebase:firebase-messaging")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:5.1.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
