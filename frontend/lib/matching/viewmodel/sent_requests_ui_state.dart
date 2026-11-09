import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/matching/model/data/sent_request.dart';

/// 보낸 신청(화면 13 가운데 섹션)의 상태. 받은 신청 · 대화 중 섹션과는 서로를 모른다.
/// [error] 는 [copyWith] 에서 덮어쓰기다 — null 로도 지워져야 한다.
class SentRequestsUiState {
  const SentRequestsUiState({
    this.isLoading = true,
    this.requests = const [],
    this.error,
  });

  final bool isLoading;

  /// 서버 순서 그대로(최신 신청 먼저).
  final List<SentRequest> requests;
  final Failure? error;

  SentRequestsUiState copyWith({
    bool? isLoading,
    List<SentRequest>? requests,
    Failure? error,
  }) {
    return SentRequestsUiState(
      isLoading: isLoading ?? this.isLoading,
      requests: requests ?? this.requests,
      error: error,
    );
  }
}
