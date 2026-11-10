package io.github.juunn.campusmate

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createDefaultNotificationChannel()
        blockScreenCaptureInRelease()
    }

    // 매니페스트의 default_notification_channel_id 가 가리키는 채널. 만들지 않으면 FCM 이
    // 앱이 뒤에 있을 때 온 알림을 "기타" 채널로 보낸다(A13). 이미 있으면 이름 · 설명만 갱신된다 —
    // 중요도는 한 번 만든 뒤엔 사용자 몫이라 여기서 올려도 반영되지 않는다.
    // 토큰 등록은 로그인 뒤라 첫 알림보다 이 화면이 늘 먼저 뜬다.
    private fun createDefaultNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "campus_mate_default",
            "CampusMate 알림",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "카드 도착 · 수락 · 매칭 · 채팅 알림" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    // 스크린샷 · 화면 녹화 · 최근 앱 미리보기를 검게 만든다. 디버그 빌드는 개발 · 홍보 캡처용이라 제외하고,
    // BuildConfig 가 없어도 되도록 앱의 debuggable 플래그로 릴리스를 가른다.
    private fun blockScreenCaptureInRelease() {
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) return
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
