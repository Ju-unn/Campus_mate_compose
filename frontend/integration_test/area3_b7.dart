part of 'area3.dart';

// 영역 3 밤 가설 E-CHAT-34 · E-CHAT-42 · E-REV-18 — 영역 4 알림 밤 판(area4_push_night.dart)의 E-PUSH-33 · 86 · 52 와 같은 판이라 앱 동작도 같다.
// PC 쪽은 e2e/area3_phone7.py(영역 4 의 같은 가설을 부른다). 앱이 하는 일은 로그인해 홈까지 가서 알림 토큰이 올라가게 두고 3초 머무는 것뿐이다(영역 1 E-ONB-61 과 같다). 새 앱 로직 없음.

final Map<String, Area1Case> area3Cases7 = {
  'E-CHAT-34': area1Cases['E-ONB-61']!,
  'E-CHAT-42': area1Cases['E-ONB-61']!,
  'E-REV-18': area1Cases['E-ONB-61']!,
};
