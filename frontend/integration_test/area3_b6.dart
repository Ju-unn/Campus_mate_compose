part of 'area3.dart';

// 영역 3 E-CHAT-53(리마인드가 밤에 걸리면 아침 8시로 밀린다 — 07시대 0건 · 08시대 1건) 한 개의 폰(B) 쪽. PC 쪽은 e2e/area3_phone6.py 의 같은 번호
// (07시대 · 08시대 chat-gate 를 한 실행에서 두 번 부르고 알림을 센다). 앱이 할 일은 로그인해 홈까지 가는 것뿐이다 — 알림 토큰 등록은 홈에 닿은 뒤 앱이 알아서 하고,
// 그 뒤 PC 가 프로세스를 죽인다(area3_b5.dart 의 E-CHAT-51 · 52 와 같다). 새 앱 로직 없음.

final Map<String, Area1Case> area3Cases6 = {
  'E-CHAT-53': _session(_homeAfterLogin),
};
