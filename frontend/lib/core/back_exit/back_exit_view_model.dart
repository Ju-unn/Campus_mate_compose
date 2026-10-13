import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 안드로이드에서 최상위 화면의 뒤로가기를 눌렀을 때 띄우는 안내 문구.
const String backExitMessage = '한 번 더 누르면 종료돼요';

/// 첫 뒤로가기 뒤 이 시간 안에 한 번 더 눌러야 앱이 닫힌다. 안내 토스트가 떠 있는 시간과 같다.
const Duration backExitWindow = Duration(seconds: 2);

/// 시험이 시간을 쥘 수 있게 시계를 밖에서 받는다.
final backExitClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 앱 전체에서 하나 — 탭을 옮겨 다녀도 "방금 눌렀다" 는 기억이 이어진다.
final backExitViewModelProvider = Provider<BackExitViewModel>(
  (ref) => BackExitViewModel(now: ref.watch(backExitClockProvider)),
);

enum BackExitAction { showHint, exit }

/// 최상위 화면에서 뒤로가기로 앱이 닫히려는 순간을 판정한다. 화면(BuildContext)은 모른다 — 시간만 본다.
class BackExitViewModel {
  BackExitViewModel({required this.now});

  final DateTime Function() now;
  DateTime? _lastBackAt;

  BackExitAction onBackPressed() {
    final current = now();
    final last = _lastBackAt;
    if (last != null && current.difference(last) < backExitWindow) {
      _lastBackAt = null;
      return BackExitAction.exit;
    }
    _lastBackAt = current;
    return BackExitAction.showHint;
  }
}
