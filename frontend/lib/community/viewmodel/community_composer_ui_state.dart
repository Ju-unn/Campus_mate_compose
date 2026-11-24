import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/data/poll.dart';

/// 17b 글쓰기 상태 — 투표 · 게시물(할 일 19). 앱 검사([canSubmit])는 미리 보여 주기만이고 기준은 서버다.
class CommunityComposerUiState {
  const CommunityComposerUiState({
    this.kind = CommunityKind.poll,
    this.category,
    this.text = '',
    this.usesDefaultOptions = true,
    this.optionA = '',
    this.optionB = '',
    this.isSubmitting = false,
    this.error,
  });

  /// 투표 / 게시물. 처음은 투표(지금 글쓰기와 같다).
  final CommunityKind kind;

  /// 고른 카테고리. **필수** — 고르기 전(null)에는 보낼 수 없다.
  final CommunityCategory? category;

  /// 게시물 본문, 투표면 질문. 입력칸 글자 그대로(보낼 때 앞뒤 공백을 뗀다).
  final String text;

  /// 투표 O/X 탭이면 true — 보기는 "찬성" · "반대" 로 정해진다. 직접 적기 탭이면 false.
  final bool usesDefaultOptions;
  final String optionA;
  final String optionB;

  /// 보내는 중(그리고 성공 뒤 화면이 닫힐 때까지). 이 동안 버튼을 끈다 — 두 번 가지 않게.
  final bool isSubmitting;

  /// 보내기 실패. 하루 한도(429)면 서버가 준 문구가 [RateLimitedFailure] 에 실려 있다(view 는 `context.errorText`).
  final Failure? error;

  /// 보낼 투표 보기 — O/X 탭이면 기본값, 직접 적기면 앞뒤 공백을 뗀 입력값.
  (String, String) pollOptions() =>
      usesDefaultOptions ? (defaultOptionA, defaultOptionB) : (optionA.trim(), optionB.trim());

  bool get canSubmit => !isSubmitting && category != null && kind.accepts(text) && _optionsFit();

  bool _optionsFit() {
    if (kind == CommunityKind.post) return true;
    final (a, b) = pollOptions();
    return pollOptionsAccepted(a, b);
  }

  static const Object _keep = Object();

  /// 안 넘기면 그대로다. [error] 는 **null 을 넘겨야** 지워진다(그래서 안 넘김과 null 을 가르는 [_keep]).
  CommunityComposerUiState copyWith({
    CommunityKind? kind,
    CommunityCategory? category,
    String? text,
    bool? usesDefaultOptions,
    String? optionA,
    String? optionB,
    bool? isSubmitting,
    Object? error = _keep,
  }) {
    return CommunityComposerUiState(
      kind: kind ?? this.kind,
      category: category ?? this.category,
      text: text ?? this.text,
      usesDefaultOptions: usesDefaultOptions ?? this.usesDefaultOptions,
      optionA: optionA ?? this.optionA,
      optionB: optionB ?? this.optionB,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: identical(error, _keep) ? this.error : error as Failure?,
    );
  }
}
