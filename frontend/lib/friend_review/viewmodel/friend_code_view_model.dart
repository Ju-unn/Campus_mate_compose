import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_errors.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_code_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 20f 를 나가면 버린다 — 다시 들어오면 빈 칸부터.
final friendCodeViewModelProvider =
    NotifierProvider.autoDispose<FriendCodeViewModel, FriendCodeUiState>(FriendCodeViewModel.new);

/// 20f 친구 코드로 리뷰 쓰기(15 "리뷰 쓰기" 줄). 코드 확인 → 결과 줄 → 20b 시트. 코드 · 닉네임은 로그에 남기지 않는다.
class FriendCodeViewModel extends Notifier<FriendCodeUiState> {
  @override
  FriendCodeUiState build() => const FriendCodeUiState();

  /// 글자가 바뀌면 지난 결과 · 오류를 지운다. 같은 글이 다시 오면(포매터가 고친 값을 또 줄 때) 그대로 둔다.
  void changeCode(String code) {
    if (code == state.code) return;
    state = FriendCodeUiState(code: code);
  }

  /// 확인 중이거나 확인할 수 없으면 아무 것도 하지 않는다 — 여러 번 눌러도 한 번만 나간다.
  Future<void> check() async {
    if (!state.canCheck) return;
    final code = state.code;
    state = FriendCodeUiState(code: code, phase: FriendCodePhase.checking);
    final result = await ref.read(friendReviewRepositoryProvider).lookupFriendCode(code);
    // 기다리는 동안 화면을 나갔거나(autoDispose) 코드를 고쳤으면 늦은 답은 버린다.
    if (!ref.mounted || state.code != code) return;
    state = result.when(onSuccess: (friend) => _found(code, friend), onFailure: (failure) => _failed(code, failure));
  }

  /// 20b 를 남기지 않고 닫았다 — 그새 썼을 수 있어(저장 409 · 보내는 중에 닫음 · 다른 기기) 다시 묻는다.
  /// 시트 반환형(bool?)은 그대로 두고 서버 답으로 맞춘다. 실패(404 · 429 · 네트워크)면 지금 확인 결과를 그대로 둔다.
  Future<void> recheck() async {
    if (state.phase != FriendCodePhase.found) return;
    final code = state.code;
    final result = await ref.read(friendReviewRepositoryProvider).lookupFriendCode(code);
    // 기다리는 동안 화면을 나갔거나 코드를 고쳤으면 버린다.
    if (!ref.mounted || state.code != code || state.phase != FriendCodePhase.found) return;
    final latest = result.when(onSuccess: (friend) => friend, onFailure: (_) => null);
    if (latest != null) state = _found(code, latest);
  }

  /// 20b 에서 남기고 돌아왔다 — 이제 이미 쓴 친구다(같은 버튼을 또 누르면 409 뿐이다).
  void markReviewed() {
    final friend = state.friend;
    if (state.phase != FriendCodePhase.found || friend == null) return;
    state = _found(
      state.code,
      FriendCodeMatch(code: friend.code, nickname: friend.nickname, university: friend.university, alreadyReviewed: true),
    );
  }

  static FriendCodeUiState _found(String code, FriendCodeMatch friend) => FriendCodeUiState(
        code: code,
        phase: friend.alreadyReviewed ? FriendCodePhase.alreadyReviewed : FriendCodePhase.found,
        friend: friend,
      );

  static FriendCodeUiState _failed(String code, Failure failure) {
    if (isFriendCodeTryLater(failure)) return FriendCodeUiState(code: code, phase: FriendCodePhase.tryLater);
    if (isFriendCodeNotFound(failure)) return FriendCodeUiState(code: code, phase: FriendCodePhase.notFound);
    return FriendCodeUiState(code: code, phase: FriendCodePhase.failed, failureMessage: failure.toDisplayMessage());
  }
}
