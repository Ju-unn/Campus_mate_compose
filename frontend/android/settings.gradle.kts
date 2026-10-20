pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    id("com.google.gms.google-services") version "4.4.4" apply false
    // 오류 수집(firebase_crashlytics, 2026-10-20 승인). 이 플러그인이 없으면 Crashlytics SDK 가 시작 때 build ID 가 없다며 앱을 죽일 수 있다.
    id("com.google.firebase.crashlytics") version "3.0.8" apply false
    // 성능 측정(firebase_performance, 2026-10-20 승인) — 자동 수집(네트워크 · 화면 렌더링)에 쓰는 바이트코드 변환 플러그인.
    id("com.google.firebase.firebase-perf") version "2.0.2" apply false
}

include(":app")
