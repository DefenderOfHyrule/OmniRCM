plugins {
    id("com.android.application")
    id("com.google.devtools.ksp")
}

android {
    namespace = "io.github.omnircm"
    compileSdk = 36
    buildToolsVersion = "35.0.0"
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "io.github.omnircm"
        minSdk = 21
        targetSdk = 36
        versionCode = 3
        versionName = "1.1.1"

        externalNativeBuild {
            cmake {
                cppFlags("-std=c++17")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.9.2")
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.9.2")
    implementation("androidx.recyclerview:recyclerview:1.4.0")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.squareup.moshi:moshi-kotlin:1.15.2")
    ksp("com.squareup.moshi:moshi-kotlin-codegen:1.15.2")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
