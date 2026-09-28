import 'package:campus_mate/common/failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 서버가 모든 인증 관문에서 헤더 `X-Account-Status` 로 알려 주는 계정 상태.
enum AccountStatus { active, suspended, withdrawn }

/// FastAPI 응답에서 본 계정 상태를 들고, 바뀌면 라우터(정지 → 안내 화면)와
/// main.dart(탈퇴 → 로그아웃)에 알린다.
///
/// 되돌리는 reset 은 없다 — 로그아웃마다 `SessionScope` 가 ProviderScope 를 새로 만들어
/// 이 값도 active 로 새로 시작한다(Ruling 36).
class AccountStatusListenable extends ChangeNotifier {
  AccountStatus _status = AccountStatus.active;

  AccountStatus get value => _status;

  /// [ApiClient] 의 모든 실패가 여기로 온다. 정지·탈퇴가 아니면 아무것도 하지 않는다.
  void observe(Failure failure) {
    switch (failure) {
      case SuspendedFailure():
        _set(AccountStatus.suspended);
      case WithdrawnFailure():
        _set(AccountStatus.withdrawn);
      default:
        return;
    }
  }

  /// 이 기기에서 탈퇴를 마쳤다(16c).
  void markWithdrawn() => _set(AccountStatus.withdrawn);

  /// 같은 값이면 알리지 않는다 — 동시에 돌아온 401 여럿이 로그아웃을 여러 번 부르지 않게.
  void _set(AccountStatus status) {
    if (status == _status) {
      return;
    }
    _status = status;
    notifyListeners();
  }
}

/// 앱 전체가 같은 상태를 본다. `apiClientProvider` 가 실패를 올리고 main.dart 가 듣는다.
final accountStatusListenableProvider = Provider<AccountStatusListenable>((ref) {
  final listenable = AccountStatusListenable();
  ref.onDispose(listenable.dispose);
  return listenable;
});
