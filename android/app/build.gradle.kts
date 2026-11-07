import com.github.triplet.gradle.androidpublisher.ReleaseStatus
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.play.publisher)
    alias(libs.plugins.ktlint)
}

fun loadProperties(file: File): Properties = Properties().apply {
    if (file.isFile) file.inputStream().use(::load)
}

// App config. android/secrets.properties (gitignored) overrides
// android/secrets.example.properties key by key, so a clean checkout builds
// with the example values.
val exampleSecrets = loadProperties(rootProject.file("secrets.example.properties"))
val localSecrets = loadProperties(rootProject.file("secrets.properties"))

fun secret(name: String): String = localSecrets.getProperty(name) ?: exampleSecrets.getProperty(name, "")

fun javaString(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

// Release signing from android/keystore.properties (gitignored). Without it a
// release builds unsigned (app-minna-release-unsigned.apk), and uploading to
// Play stops with a message.
val keystoreFile = rootProject.file("keystore.properties")
val keystore = loadProperties(keystoreFile)
val hasReleaseKeystore = keystoreFile.isFile
if (hasReleaseKeystore) {
    val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { keystore.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "android/keystore.properties is missing ${missing.joinToString()}. " +
                "See android/keystore.example.properties."
        )
    }
    if (!rootProject.file(keystore.getProperty("storeFile")).isFile) {
        throw GradleException(
            "android/keystore.properties: storeFile does not point to a file " +
                "(a relative path is resolved from android/)."
        )
    }
}
// Firebase config (gitignored). Without it the Firebase plugins stay off and Firebase is not initialised.
val hasGoogleServices = file("google-services.json").isFile

val uploadTask = Regex("(?i)(^|:)publish(\\w*(bundle|apk))?$")
val unsignedUploadMessage =
    "Uploading to Play needs a signed release: copy android/keystore.example.properties " +
        "to android/keystore.properties and fill it in (android/README.md, Release)."
// From the command line: stop before anything builds.
if (!hasReleaseKeystore && gradle.startParameter.taskNames.any { uploadTask.containsMatchIn(it) }) {
    throw GradleException(unsignedUploadMessage)
}
// Any other way in (an IDE run configuration, a dependent task): stop before
// the upload task's own action runs.
tasks.matching { uploadTask.containsMatchIn(it.name) }.configureEach {
    val signed = hasReleaseKeystore
    val message = unsignedUploadMessage
    doFirst { if (!signed) throw GradleException(message) }
}

// The generated course data is a build input read in place, not a copy: scripts/build-minna-data.py
// writes MinnaData.json, KanaChart.json and audio/ into nihongo/Resources, and the minna flavour
// packages that folder as its assets.
val minnaResources = rootProject.file("../nihongo/Resources")

android {
    namespace = "com.kfpun.japanesedaily"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.kfpun.japanesedaily"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        // Pinned by IdentityTest: the FOX-146 decisions, readable from a JVM test.
        buildConfigField("int", "MIN_SDK", minSdk.toString())
        buildConfigField("int", "TARGET_SDK", targetSdk.toString())

        // Directus (survey rows, FOX-157). The example file carries a placeholder token.
        buildConfigField("String", "DIRECTUS_URL", javaString(secret("DIRECTUS_URL")))
        buildConfigField("String", "DIRECTUS_TOKEN", javaString(secret("DIRECTUS_TOKEN")))
        // AdMob (FOX-158). The example file holds Google's test ids.
        manifestPlaceholders["ADMOB_APP_ID"] = secret("ADMOB_APP_ID")
        listOf(
            "AD_UNIT_ID_TODAY",
            "AD_UNIT_ID_PROGRESS",
            "AD_UNIT_ID_KANA",
            "AD_UNIT_ID_LESSONS",
            "AD_UNIT_ID_SELECT_MODE",
            "AD_UNIT_ID_VOCAB_LIST",
            "AD_UNIT_ID_SEARCH",
            "AD_UNIT_ID_ABOUT",
            "AD_UNIT_ID_INTERSTITIAL"
        ).forEach { buildConfigField("String", it, javaString(secret(it))) }
    }

    flavorDimensions += "course"
    productFlavors {
        // Minna no Nihongo vocabulary. JLPT follows as a second flavour in the same dimension.
        create("minna") {
            dimension = "course"
        }
    }

    sourceSets {
        // KanjiStrokeOrders (and its licence) is the same file iOS bundles and the handwriting scoring
        // template, so it is packaged from nihongo/Fonts in place, not copied. Fonts are not generated
        // files. Noto Serif JP lives in src/main/assets/fonts with its OFL text in assets/licenses.
        getByName("main") {
            assets.directories.add(rootProject.file("../nihongo/Fonts").path)
        }
        getByName("minna") {
            assets.directories.add(minnaResources.path)
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystore.getProperty("storeFile"))
                storePassword = keystore.getProperty("storePassword")
                keyAlias = keystore.getProperty("keyAlias")
                keyPassword = keystore.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        // Debug builds never report to Analytics or Crashlytics (FOX-160); release builds report
        // unless the install opted out.
        // Like iOS DEBUG, a debug build is excluded. FIREBASE_DEBUG_COLLECTION=true in secrets.properties
        // turns collection on for checking events in DebugView (android/README.md, Analytics).
        debug {
            val collect = secret("FIREBASE_DEBUG_COLLECTION") == "true"
            manifestPlaceholders["FIREBASE_COLLECTION_ENABLED"] = collect.toString()
            buildConfigField("boolean", "FIREBASE_COLLECTION", collect.toString())
        }
        release {
            manifestPlaceholders["FIREBASE_COLLECTION_ENABLED"] = "true"
            buildConfigField("boolean", "FIREBASE_COLLECTION", "true")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else null
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // The audio clips are read through AssetFileDescriptor, which needs them stored uncompressed.
    androidResources {
        noCompress += listOf("m4a", "mp3")
    }

    testOptions {
        // Robolectric (the Room tests) reads the merged manifest and resources.
        unitTests.isIncludeAndroidResources = true
        // android.util.Log and friends return defaults in JVM tests instead of throwing.
        unitTests.isReturnDefaultValues = true
    }

    // The in-app language picker (FOX-150) switches to a language the phone may not use, so
    // the bundle keeps every language in the base APK instead of splitting them by locale.
    bundle {
        language {
            enableSplit = false
        }
    }

    lint {
        abortOnError = true
        checkReleaseBuilds = true
    }
}

// Fail early and clearly when the generated data is missing, instead of shipping an empty app.
val checkMinnaData = tasks.register("checkMinnaData") {
    val data = minnaResources.resolve("MinnaData.json")
    doFirst {
        if (!data.isFile) {
            throw GradleException(
                "nihongo/Resources/MinnaData.json is missing. Generate the course data first: " +
                    "git submodule update --init minna && python3 scripts/build-minna-data.py " +
                    "(android/README.md, Setup)."
            )
        }
    }
}
tasks.matching { it.name.matches(Regex("merge\\w*Assets")) }.configureEach { dependsOn(checkMinnaData) }

// Firebase (Crashlytics and Analytics, nothing else). The plugins need
// app/google-services.json, which is gitignored, so they apply only when it is
// there. Without it the app still builds and Firebase stays uninitialised.
if (hasGoogleServices) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
    apply(plugin = libs.plugins.firebase.crashlytics.get().pluginId)
}

// Play upload (Gradle Play Publisher) to the internal track, as a draft the
// user rolls out in Play Console. The service-account JSON is gitignored; its
// path comes from PLAY_SERVICE_ACCOUNT_JSON in secrets.properties.
play {
    track.set("internal")
    releaseStatus.set(ReleaseStatus.DRAFT)
    defaultToAppBundles.set(true)
    val credentials = rootProject.file(secret("PLAY_SERVICE_ACCOUNT_JSON").ifBlank { "play-service-account.json" })
    if (credentials.isFile) serviceAccountCredentials.set(credentials)
}

ktlint {
    version.set("1.8.0")
}

// Room exports its schema so a later migration can be tested against the shipped version.
ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.appcompat)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.analytics)
    implementation(libs.firebase.crashlytics)

    // Data layer (FOX-148): course JSON, Room progress tables, DataStore preferences.
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
}
