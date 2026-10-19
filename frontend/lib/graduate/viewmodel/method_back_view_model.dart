import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 뒤로가기가 서버 값을 비우는 중인지, 실패했는지. 오류 문구는 화면이 짧은 안내로 한 번 띄운다.
class MethodBackUiState {
  const MethodBackUiState({this.isLeaving = false, this.errorMessage});

  final bool isLeaving;
  final String? errorMessage;
}

/// 앱을 닫아도 남는 상태이므로 화면 하나에 묶지 않는다(02 · 신청 폼이 같은 것을 쓴다).
final methodBackViewModelProvider = NotifierProvider<MethodBackViewModel, MethodBackUiState>(MethodBackViewModel.new);

/// 신청 폼 · 학교 메일(02) → 방법 고르기로 돌아가는 뒤로가기(앱바 화살표 · 안드로이드 시스템 뒤로 둘 다).
///
/// 서버 값이 `school_email`/`graduate_certificate` 인 채로 화면만 옮기면 리다이렉트가 도로 끌고 오므로
/// **서버 값을 먼저 비우고**(`PUT {"method": null}`), 성공하면 관문을 다시 묻는다 — 화면은 `AuthRedirect` 가 옮긴다.
/// 비우지 못하면(인터넷 없음) 그 자리에 머문다: 관문을 건드리지 않고 오류 문구만 둔다.
class MethodBackViewModel extends Notifier<MethodBackUiState> {
  @override
  MethodBackUiState build() => const MethodBackUiState();

  /// 가는 중에 또 누르면 무시한다 — 서버 쓰기는 한 번만 나간다.
  Future<void> goBack() async {
    if (state.isLeaving) return;
    state = const MethodBackUiState(isLeaving: true);
    final result = await ref.read(graduateVerificationRepositoryProvider).chooseMethod(null);
    if (!ref.mounted) return;
    final failure = result.when(onSuccess: (_) => null, onFailure: (failure) => failure);
    final message = failure == null ? await _refreshGateMessage() : failure.toDisplayMessage();
    if (!ref.mounted) return;
    state = MethodBackUiState(errorMessage: message);
  }

  /// 서버 값은 비웠는데 관문을 다시 묻지 못하면 화면이 안 옮겨져 아무 일도 없는 것처럼 보인다 — 같은 실패 안내를 남긴다.
  /// 묻기 실패는 원인을 주지 않아(`refresh` 는 true · false 뿐) 네트워크 문구로 한다.
  Future<String?> _refreshGateMessage() async {
    final refreshed = await ref.read(verificationGateListenableProvider).refresh();
    return refreshed ? null : const NetworkFailure().toDisplayMessage();
  }
}
