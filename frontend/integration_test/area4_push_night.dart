part of 'area4.dart';

// 영역 4 PUSH 밤·아침·시각 경계 13개 — 알림이 오는지 · 안 오는지만 보는 가설. PC 쪽은 e2e/area4_push_night.py 의 같은 번호
// (계정 · 상대 행동 · 보관 행 · 알림 읽기는 전부 PC). 앱이 하는 일은 하나다 — 로그인해 홈까지 가서 알림 토큰이 올라가게 두고 3초 머문다(영역 1 E-ONB-61 과 같은 동작).
// 아침 단계는 앱을 다시 켜 같은 일을 한다(받는 사람 계정으로 다시 로그인).

const _pushNightHomeCases = ['15', '16', '23', '33', '52', '72', '73', '83', '84', '85', '86', '87', '88'];

final Map<String, Area1Case> _pushNightCases = {
  for (final number in _pushNightHomeCases) 'E-PUSH-$number': area1Cases['E-ONB-61']!,
};
