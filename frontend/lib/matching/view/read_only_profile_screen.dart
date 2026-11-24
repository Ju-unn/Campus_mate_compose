import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/retry_notice.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/matching/model/data/card_detail.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/profile_avatar_header.dart';
import 'package:campus_mate/matching/viewmodel/acceptance_detail_view_model.dart';
import 'package:campus_mate/matching/viewmodel/card_detail_view_model.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 이미 결정한 카드의 상대를 다시 보는 읽기 전용 프로필. 결정 버튼(거절 · 대화 신청하기)이 없다.
/// - 10b-2 보낸 신청 · 프로필 보기(pen ig7i2, 제목 "보낸 신청") — 보낸 신청 줄의 [프로필 보기] 가 push 로 연다.
/// - 10b-3 거절한 카드 · 프로필 보기(pen hhlWE, 제목 "거절한 카드" + 아래 버튼 하나)도 [title] · [bottomAction] 만 바꿔 쓴다.
///
/// 읽기는 10b 와 같은 `GET /cards/{card_id}`([CardDetailViewModel]) — 서버는 결정한 카드도 주인에게 돌려주고,
/// 상대가 차단 · 정지 · 탈퇴 · 가림이거나 이미 매칭된 상대면 404 다(`backend/app/cards/router.py` `get_card_detail`).
/// 본문은 10b 카드([ProfileCard] + 아바타 칸)다 — 수락 전이라 사진은 아바타만이다.
/// 시안에 없는 상태는 10b 의 도는 표시 · 회색 글자([DetailMessage], 숨김 · 404)와 공용 [RetryNotice](연결 실패)로 그린다
/// (대장 판정 9 · 16-2).
class ReadOnlyProfileScreen extends ConsumerWidget {
  const ReadOnlyProfileScreen({
    required this.cardId,
    required this.title,
    this.bottomAction,
    this.readsAcceptance = false,
    super.key,
  });

  final String cardId;

  /// 앱바 제목(AppBar · Sub `KH1hX` 18/700) — "보낸 신청" / "거절한 카드".
  final String title;

  /// 카드 아래 14 에 함께 스크롤하는 버튼(10b 결정 버튼 자리, pen hhlWE "다시 신청하기"). 보낸 신청은 없다.
  final Widget? bottomAction;

  /// 받은 신청을 거절한 줄(거절한 카드 출처 acceptance)은 카드 주인이 상대라 카드 읽기가 404 다 —
  /// 받은 신청 읽기(`GET /cards/acceptances/{card_id}`, 되돌릴 수 있는 거절이면 서버가 연다)로 읽는다.
  final bool readsAcceptance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:detail, :error, :retry) = readsAcceptance ? _readAcceptance(ref) : _readCard(ref);
    return Scaffold(
      appBar: EditAppBar(title: title),
      // pen ig7i2 `cT6qP` · hhlWE `YTn3s`: 10b 와 같은 하단 내비, 대화 탭 선택.
      bottomNavigationBar: const AppBottomNav(current: AppTab.chat),
      body: SafeArea(
        child: switch (detail) {
          // 10b 와 같은 가운데 회색 글자 — 숨김 · 없음은 다시 해도 같다(대장 판정 16-2).
          null when error != null && _isFinal(error) => DetailMessage(text: context.errorText(error)),
          null when error != null =>
            RetryNotice(message: context.errorText(error), onRetry: retry),
          null => const Center(child: CircularProgressIndicator()),
          _ => _Body(detail: detail, bottomAction: bottomAction),
        },
      ),
    );
  }

  _Read _readCard(WidgetRef ref) {
    final provider = cardDetailViewModelProvider(cardId);
    final state = ref.watch(provider);
    return (detail: state.detail, error: state.error, retry: ref.read(provider.notifier).load);
  }

  /// 받은 신청 읽기는 들어올 때마다 새로 읽는(autoDispose) 뷰모델이라 다시 시도는 새로 만들어 읽는다.
  _Read _readAcceptance(WidgetRef ref) {
    final provider = acceptanceDetailViewModelProvider(cardId);
    final state = ref.watch(provider);
    return (detail: state.detail, error: state.error, retry: () => ref.invalidate(provider));
  }
}

typedef _Read = ({CardDetail? detail, Failure? error, VoidCallback retry});

/// 다시 읽어도 결과가 같은 실패. 서버 404(상대 숨김 · 없음 `CARD_NOT_FOUND`)는 `http_send` 가 상태 코드를 버리고
/// 서버 문구를 든 [ServerRejectedFailure] 로 넘기므로 4xx 거절 전체를 여기로 본다. 연결 · 5xx 는 다시 시도를 둔다.
bool _isFinal(Failure failure) => failure is ServerRejectedFailure || failure is NotFoundFailure;

class _Body extends StatelessWidget {
  const _Body({required this.detail, required this.bottomAction});

  final CardDetail detail;
  final Widget? bottomAction;

  /// 카드 → 아래 버튼(10b `TORAs` 결정 버튼과 같은 14).
  static const double _actionGap = 14;

  @override
  Widget build(BuildContext context) {
    final action = bottomAction;
    return SingleChildScrollView(
      // 카드가 앱바에 바로 붙는다(pen ZGYbU padding [0,16], 10b 와 같은 본문 여백).
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileCard(detail: detail, header: ProfileAvatarHeader(url: detail.profile.avatarUrl)),
          if (action != null) ...[const SizedBox(height: _actionGap), action],
        ],
      ),
    );
  }
}
