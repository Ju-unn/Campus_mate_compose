import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/viewmodel/withdraw_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시트를 열 때마다 새로 시작한다 — 지난번 실패 문구가 남지 않게.
final withdrawViewModelProvider =
    NotifierProvider.autoDispose<WithdrawViewModel, WithdrawUiState>(WithdrawViewModel.new);

/// 16c 탈퇴. 로그아웃은 하지 않는다 — 계정 상태만 withdrawn 으로 바꾸면
/// main.dart 리스너 한 곳이 알림을 남기고 로그아웃한다(두 곳에서 부르지 않는다).
class WithdrawViewModel extends Notifier<WithdrawUiState> {
  @override
  WithdrawUiState build() => const WithdrawUiState();

  Future<void> withdraw() async {
    if (state.isSubmitting) {
      return;
    }
    state = const WithdrawUiState(isSubmitting: true);
    // 응답 전에 시트가 닫혀 이 ViewModel 이 버려져도 탈퇴는 이미 됐다 — 상태를 올릴 곳을 먼저 잡아 둔다.
    final accountStatus = ref.read(accountStatusListenableProvider);
    final result = await ref.read(accountRepositoryProvider).withdraw();
    result.when<void>(
      onSuccess: (_) => accountStatus.markWithdrawn(),
      onFailure: (failure) => _onFailure(failure, accountStatus),
    );
  }

  /// 응답이 끊겨 다시 누르면 401 + withdrawn 이 온다 — 원하던 결과가 이미 났으니 성공이다.
  void _onFailure(Failure failure, AccountStatusListenable accountStatus) {
    if (failure is WithdrawnFailure) {
      accountStatus.markWithdrawn();
      return;
    }
    if (ref.mounted) {
      state = WithdrawUiState(errorMessage: failure.toDisplayMessage());
    }
  }
}
