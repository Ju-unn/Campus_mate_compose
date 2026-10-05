part of 'area4.dart';

// 영역 4 PUSH A1 — 알림이 오는지 · 안 오는지만 보는 21개. PC 쪽은 e2e/area4_push.py 의 같은 번호(계정 · 상대 행동 · 알림 읽기는 전부 PC).
// 앱이 하는 일은 하나다 — 로그인해 홈까지 가서 알림 토큰이 올라가게 두고 3초 머문다(영역 1 E-ONB-61 과 같은 동작). 알림 확인은 PC 가 한다.
// 54 는 영역 2 E-REF-18 과 같은 가설이라 PC 쪽이 그 함수를 그대로 쓴다.

const _pushHomeCases = ['10', '12', '13', '17', '18', '21', '22', '24', '25', '26', '32', '34', '35', '36', '37', '39', '49', '51', '54', '70', '74'];

final Map<String, Area1Case> _pushCases = {
  for (final number in _pushHomeCases) 'E-PUSH-$number': area1Cases['E-ONB-61']!,
};
