/// 시작 화면 로고를 빠르게 여러 번 눌렀는지 센다 — 구글 플레이 심사원 로그인 창으로 들어가는 숨은 입구의 판정.
///
/// "한도 안에 [taps] 번째 탭" 이면 true 를 돌려주고 처음부터 다시 센다. 시간은 부르는 쪽이 넘긴다(시계를 몰라 시험이 쉽다).
class TapStreak {
  /// 열리는 탭 횟수. 숨은 입구라 실수로 열리지 않을 만큼 많고, 심사 안내문에 적기에 부담 없는 7번이다(사용자 결정 2026-11-04).
  static const int taps = 7;

  /// 이 시간이 지난 탭은 세지 않는다. 안내문을 읽으며 또박또박(초당 1.5번쯤) 7번 누르면 4.7초라 5초로 잡았다 —
  /// 4초는 느린 손에 빠듯하고, 일반 사용자가 이 자리를 5초에 7번 누를 일은 없다.
  static const Duration window = Duration(seconds: 5);

  final List<DateTime> _times = [];

  /// [now] 에 탭이 하나 있었다. 이 탭으로 [taps] 번이 찼으면 true — 그때 세기를 비운다.
  bool register(DateTime now) {
    _times.removeWhere((time) => now.difference(time) > window);
    _times.add(now);
    if (_times.length < taps) {
      return false;
    }
    _times.clear();
    return true;
  }
}
