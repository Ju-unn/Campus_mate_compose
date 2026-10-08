import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// 카카오 네이티브 앱 키 — 카카오 로그인 복귀 스킴(kakao{키}://oauth)에 쓴다. 저장소에 값을 쓰지 않는다.
// 환경변수 KAKAO_NATIVE_APP_KEY, 없으면 local.properties(gitignore 대상)의 같은 이름, 그것도 없으면 빈 문자열
// (키 없이도 빌드는 된다 — 그때 앱의 카카오 버튼은 실패 토스트). 앱 코드는 같은 키를 --dart-define 으로 따로 받는다.
val kakaoNativeAppKey: String = System.getenv("KAKAO_NATIVE_APP_KEY")
    ?: Properties().apply {
        val localProperties = rootProject.file("local.properties")
        if (localProperties.exists()) {
            localProperties.inputStream().use { load(it) }
        }
    }.getProperty("KAKAO_NATIVE_APP_KEY")
    ?: ""

android {
    namespace = "io.github.juunn.campusmate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 스토어 등록 후에는 변경 불가 (설계 문서 §1)
        applicationId = "io.github.juunn.campusmate"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AndroidManifest 의 카카오 복귀 activity 스킴 kakao${kakaoKey}
        manifestPlaceholders["kakaoKey"] = kakaoNativeAppKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
