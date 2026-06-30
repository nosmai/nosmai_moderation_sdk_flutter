import java.net.URI

group = "com.nosmai.nosmai_moderation_sdk"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.nosmai.nosmai_moderation_sdk"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

// The Nosmai SDK AAR (~100 MB) is intentionally NOT committed — it exceeds the
// pub.dev and Git file-size limits. Download it from the published GitHub release
// so the plugin can compile against the SDK API (compileOnly). The host app must
// add the SAME AAR to its own app/libs/ at implementation scope (see README),
// because AGP cannot bundle a local .aar inside this plugin's AAR.
val nosmaiAarVersion = "1.0.0"
val nosmaiAar = layout.projectDirectory.file("libs/nosmai-detection.aar").asFile

val downloadNosmaiAar by tasks.registering {
    outputs.file(nosmaiAar)
    onlyIf { !nosmaiAar.exists() }
    doLast {
        nosmaiAar.parentFile.mkdirs()
        val url = "https://github.com/nosmai/moderation-sdk-android/releases/" +
            "download/$nosmaiAarVersion/nosmai-detection.aar"
        logger.lifecycle("Nosmai: downloading SDK AAR -> $nosmaiAar")
        URI(url).toURL().openStream().use { input ->
            nosmaiAar.outputStream().use { input.copyTo(it) }
        }
    }
}

tasks.matching { it.name.startsWith("compile") }.configureEach {
    dependsOn(downloadNosmaiAar)
}

dependencies {
    // Nosmai Detection SDK — prebuilt AAR (libs/nosmai-detection.aar, downloaded
    // above): bundles the native libnosmai_jni.so (NCNN statically linked) +
    // libonnxruntime.so + the encrypted model assets. compileOnly because a
    // Flutter plugin is itself built as an AAR and AGP cannot bundle a local .aar
    // inside another AAR — the host app packages the .aar instead (see
    // example/android/app/build.gradle.kts).
    compileOnly(files("libs/nosmai-detection.aar"))

    // CameraX powers the native live-camera preview + frame analysis.
    val cameraxVersion = "1.4.2"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
