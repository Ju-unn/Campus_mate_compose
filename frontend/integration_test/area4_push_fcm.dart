part of 'area4.dart';

// 영역 4 PUSH — FCM 으로 직접 보낸 알림을 눌렀을 때(E-PUSH-56 · 57). PC 쪽은 e2e/area4_push_fcm.py 의 같은 번호 —
// 계정 · FCM 발송 · 알림창 읽기와 누르기는 전부 PC, 앱은 홈에서 멈춰 기다리다(`holding`) 눌린 뒤 화면에서 본 것만 말한다.
//   56  data.route = zzz  → 앱이 앞으로 오되 화면은 그대로(홈이 남고 대화 목록 · 방 · 받은 리뷰는 안 뜸)
//   57  data.route = chat 에 match_id 없음 → 대화 목록(13)
// 이 파일은 기기에서 아직 안 돌려 봤다.

const _fcmSettle = Duration(seconds: 5); // 눌린 뒤 라우터가 경로를 옮길 시간 — 56 은 "안 옮겨짐" 을 보려고 이만큼은 기다린다

/// 지금 보이는 화면 — 홈이 남았나 · 목적지가 될 수 있는 세 화면이 떴나.
Map<String, Object?> _fcmWhere() => {
      'home': screen('home').evaluate().isNotEmpty,
      'conversations': find.byType(ConversationsScreen).evaluate().isNotEmpty,
      'room': find.byType(ChatRoomScreen).evaluate().isNotEmpty,
      'reviews': find.byType(ReceivedReviewsScreen).evaluate().isNotEmpty,
    };

Future<Map<String, Object?>?> _fcmHold(WidgetTester tester, Map<String, dynamic> job, Future<Map<String, Object?>> Function() look) =>
    _session((tester, job) async {
      await arrive(tester, 'home');
      await wait(tester, const Duration(seconds: 3));
      await step('holding', timeout: const Duration(minutes: 4)); // PC 가 HOME · 발송 · 알림 읽기 · 누르기를 하는 동안
      return look();
    })(tester, job);

final Map<String, Area1Case> _pushFcmCases = {
  'E-PUSH-56': (tester, job) => _fcmHold(tester, job, () async {
        await wait(tester, _fcmSettle);
        return _fcmWhere();
      }),
  'E-PUSH-57': (tester, job) => _fcmHold(tester, job, () async {
        await appears(tester, find.byType(ConversationsScreen), const Duration(seconds: 30));
        return _fcmWhere();
      }),
};
