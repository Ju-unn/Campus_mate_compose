import 'package:campus_mate/account/viewmodel/account_info_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/me/view/me_tab_bar.dart';
import 'package:campus_mate/me/viewmodel/card_preview_provider.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/safety/view/revealed_profile_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 15-4 / 15-4b 남이 보는 내 프로필(pen `gnEwq` 수락 전 · `vn8R2` 수락 후). 화면 15 입구 "남이 보는 내 프로필 카드"(`k3r5C`)가 연다.
/// 하단 내비 없음. 앱바 아래 밑줄 탭 바("수락 전" · "수락 후")가 두 모양을 가른다 — 처음엔 수락 전.
///
/// 카드는 10b · 14c 가 같이 쓰는 [ProfileCard] 다. 수락 전은 실사진 · 카카오 카드 · 신고/차단 줄 · "신뢰 확인 완료"(`CTtPd`)가
/// 없는 모양(pen `kpIeX`)이고, 수락 후는 14c 가 쓰는 조각([RevealedPhotoHeader] · [KakaoIdCard])을 그대로
/// 얹어 상대가 수락한 뒤 보게 될 모양을 미리 보여 준다. 신고/차단 줄은 14c 에만 있다 — 내가 내 프로필을 볼 때는 누를 곳이 없어
/// 앱에서만 뺐다(사용자 결정 2026-10-10 · pen `vn8R2` 안 신고/차단 줄은 그대로 둠, 같은 그림을 상대 프로필이 쓴다). 값은 `GET /me/card-preview`(10b 와 같은 몸통, 계획서 N2) +
/// 내 프로필의 실사진 · 계정의 카카오톡 아이디.
class CardPreviewScreen extends ConsumerStatefulWidget {
  const CardPreviewScreen({super.key});

  @override
  ConsumerState<CardPreviewScreen> createState() => _CardPreviewScreenState();
}

class _CardPreviewScreenState extends ConsumerState<CardPreviewScreen> {
  static const List<String> _tabs = ['수락 전', '수락 후'];

  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    // 화면이 떠 있는 동안 두 값을 살려 둔다 — accountInfoProvider 는 autoDispose 라 "수락 후" 를 떠날 때마다 버려져
    // 탭을 오갈 때마다 계정을 다시 읽고 도는 표시가 다시 뜬다. 처음 한 번 미리 읽어 "수락 후" 로 바꿀 때 바로 보이게도 한다.
    ref.watch(accountInfoProvider);
    ref.watch(myProfileProvider);
    return Scaffold(
      appBar: const EditAppBar(title: '남이 보는 내 프로필'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            MeTabBar(labels: _tabs, selected: _selected, onSelected: (index) => setState(() => _selected = index)),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  /// 불러오는 중 · 실패는 pen 에 없는 상태다 — 화면 15 와 같은 모양(가운데 로딩 / [MeLoadError], 계획서 N9).
  Widget _body() {
    void retry() => ref.invalidate(myCardPreviewProvider);
    return ref
        .watch(myCardPreviewProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => MeLoadError(onRetry: retry),
          data: (result) => result.when(
            onSuccess: (detail) => _selected == 0 ? _BeforeAccept(detail: detail) : _AfterAccept(detail: detail),
            onFailure: (_) => MeLoadError(onRetry: retry),
          ),
        );
  }
}

/// 본문 아래 여백 40 은 pen 값(간격 토큰 xl 32 · xxl 48 사이).
const double _bodyBottom = 40;

/// 본문 `iFAyO` — 위 24 · 좌우 16 · 아래 40, 안내 ↔ 카드 32. 카드 높이는 내용 맞춤(N17).
/// 위 24 는 탭 바의 누르는 칸이 보이는 줄 아래로 더한 만큼([MeTabBar.extraHitHeight])을 뺀 값이다 — 안내의 보이는 자리는 pen 그대로(탭 바 아래 24).
const EdgeInsets _bodyPadding = EdgeInsets.fromLTRB(
  AppSpacing.md,
  AppSpacing.lg - MeTabBar.extraHitHeight,
  AppSpacing.md,
  _bodyBottom,
);

/// 15-4 수락 전: 안내(`Ocmk4`) + 실사진 · 카카오 카드가 없는 카드.
class _BeforeAccept extends StatelessWidget {
  const _BeforeAccept({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _bodyPadding,
      children: [
        const _PreviewNotice(text: '대화 상대가 보는 내 프로필이에요. 실제 사진과 카카오톡 아이디는 둘 다 수락한 뒤에 공개돼요.'),
        const SizedBox(height: AppSpacing.xl),
        // 지인 리뷰 섹션(kpIeX 안) — 채팅탭 지인 리뷰 PR 4 가 넣는다(깃발 숨김 N6).
        ProfileCard(detail: detail),
      ],
    );
  }
}

/// 15-4b 수락 후: 안내(`J7rLm`) + 실사진 슬라이더 · 카카오톡 아이디 카드가 붙은 카드(신고/차단 줄 없음).
///
/// 실사진은 내 프로필의 사진들, 카카오톡 아이디는 내 계정의 값이다(pen 의 사진 · "hong_gildong" 은 예시). 둘을 다 읽을 때까지
/// 가운데 도는 표시를 보인다(카드가 나중에 늘어나 튀지 않게). 읽지 못한 쪽은 그 칸만 빠진다 — pen 에 없는 상태.
class _AfterAccept extends ConsumerWidget {
  const _AfterAccept({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    final account = ref.watch(accountInfoProvider);
    if (profile.isLoading || account.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final urls =
        profile.value?.when(
          onSuccess: (value) => [for (final photo in value.photos) photo.url],
          onFailure: (_) => <String>[],
        ) ??
        const <String>[];
    final kakaoId = account.value?.when(onSuccess: (value) => value.kakaoId, onFailure: (_) => null);
    return ListView(
      padding: _bodyPadding,
      children: [
        const _PreviewNotice(text: '수락하면 상대에게 이렇게 보여요'),
        const SizedBox(height: AppSpacing.xl),
        ProfileCard(
          detail: detail,
          // 사진이 없으면(읽기 실패 · 0장) 슬라이더 칸이 없다 — 14c 와 같다.
          header: urls.isEmpty ? null : RevealedPhotoHeader(urls: urls),
          // 카카오 카드가 없으면 footer 도 없다 — 카드 기본 아래 여백 20 이 맨 끝을 받는다(수락 전 카드와 같은 끝).
          footer: kakaoId == null || kakaoId.isEmpty
              ? null
              : _AfterAcceptFooter(afterIdealNote: detail.idealNote != null, kakaoId: kakaoId),
        ),
      ],
    );
  }
}

/// 카드 맨 아래(14c `_Footer` 와 같은 틀에서 지인 리뷰 · 신고/차단 줄을 뺀다): [13] → 카카오 카드 → 20.
/// 신고/차단 줄이 빠져 footer 가 가져간 카드 아래 여백(footer 가 있으면 0)을 기본값 20 으로 되돌려 준다.
class _AfterAcceptFooter extends StatelessWidget {
  const _AfterAcceptFooter({required this.afterIdealNote, required this.kakaoId});

  final bool afterIdealNote;
  final String kakaoId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (afterIdealNote) const SizedBox(height: 13),
        KakaoIdCard(kakaoId: kakaoId),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// 안내(Notice `WQIrY`) — primary-wash, 모서리 12, 안쪽 14, 아이콘 · 링크 없음, 14/400 body 줄높이 1.5.
class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice({required this.text});

  final String text;

  /// 모서리 12 · 안쪽 14 는 pen 값(토큰 사이 값 — 라운드 sm 8 · md 14, 간격 sm 12 · md 16).
  static const double _radius = 12;
  static const double _padding = 14;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(_radius)),
      child: Padding(
        padding: const EdgeInsets.all(_padding),
        child: Text(text, style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.body)),
      ),
    );
  }
}
