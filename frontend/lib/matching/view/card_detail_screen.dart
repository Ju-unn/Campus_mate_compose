import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/card_action_bar.dart';
import 'package:campus_mate/common/widgets/trait_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/viewmodel/card_detail_view_model.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 10b 상대 프로필 상세 · 결정(pen `TORAs`). 실사진·카카오톡 아이디는 여기에도 없다 —
/// 그건 신뢰 확인(조각 5) 뒤다. 신고·차단 진입점은 조각 6 이 붙인다.
///
/// 2026-09-23 pen 대조: 앱바·하단 내비가 "오늘" 탭과 같고, 본문은 카드 한 장 안에 들어간다.
/// 맨 위 큰 원형 아바타는 시안에 없어 뺐다 — 카드 앞면(10)에서 이미 본 그림이다.
class CardDetailScreen extends ConsumerWidget {
  const CardDetailScreen({required this.cardId, super.key});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = cardDetailViewModelProvider(cardId);
    final state = ref.watch(provider);
    // 결정이 끝나면 오늘 탭으로 돌아간다. 수락이 쌍방이어도 여기서 매칭 화면으로 가지 않는다 —
    // 상대의 수락은 나중에 오고, 매칭 성사(12)는 받은 수락함에서만 일어난다.
    ref.listen(provider, (previous, next) {
      if (next.decided && !(previous?.decided ?? false) && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });

    final detail = state.detail;
    return Scaffold(
      // 10 과 같은 탭 앱바다 — 카드를 열어도 "오늘" 탭 안에 있다는 것을 유지한다.
      appBar: AppBar(
        // 8 + 48 에 titleSpacing 4 — pen 처럼 화살표 가운데 x32, 제목 x60 이 된다.
        leadingWidth: 56,
        titleSpacing: 4,
        leading: Navigator.of(context).canPop()
            ? const Padding(
                padding: EdgeInsets.only(left: 8),
                child: BackButton(color: AppColors.ink),
              )
            : null,
        title: Text('오늘의 카드', style: AppTypography.navTitle),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.today),
      body: SafeArea(
        child: switch (detail) {
          null when state.errorMessage != null => _Message(text: state.errorMessage!),
          null => const Center(child: CircularProgressIndicator()),
          _ => _DetailBody(
            detail: detail,
            errorMessage: state.errorMessage,
            onReject: state.isSubmitting
                ? null
                : () => ref.read(provider.notifier).decide(CardDecision.reject),
            onAccept: state.isSubmitting
                ? null
                : () => ref.read(provider.notifier).decide(CardDecision.accept),
          ),
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.muted),
        ),
      ),
    );
  }
}

/// 카드 안 섹션 사이 간격. 토큰 sm(12)·md(16) 사이 pen 실측값이다.
const double _sectionGap = 13;

/// DESIGN.md §8.5 문항 표의 양 끝 라벨. 순서는 05-01 활동성 … 05-09 새로움이다.
/// 10b 는 바가 좁아 **짧은 말**을 쓴다 — 04-5 설문(입력)의 긴 문장과 일부러 다르다.
const _axisLabels = <({String left, String right})>[
  (left: '집콕', right: '밖으로'),
  (left: '낯가림', right: '금방 친해짐'),
  (left: '즉흥적', right: '계획적'),
  (left: '가끔', right: '자주'),
  (left: '담백', right: '표현 풍부'),
  (left: '안 마심', right: '자주 마심'),
  (left: '안 함', right: '꾸준히'),
  (left: '천천히', right: '빠르게'),
  (left: '익숙한 것', right: '새로운 것'),
];

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.onReject,
    required this.onAccept,
    this.errorMessage,
  });

  final CardDetail detail;
  final String? errorMessage;
  final VoidCallback? onReject;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // 카드가 앱바에 바로 붙는다(pen `TORAs`) — 위 여백만 0 이다.
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileCard(detail: detail),
          // 버튼은 카드 밖 14 아래에 붙어 함께 스크롤한다(pen `TORAs`).
          const SizedBox(height: 14),
          CardActionBar(onReject: onReject, onAccept: onAccept),
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    final profile = detail.profile;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.nameWithAge,
            style: AppTypography.title.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _SchoolLine(detail: detail),
          if (detail.bio != null) ...[
            const _CardDivider(),
            // 자기소개는 사실 칸보다 먼저 온다 — 사람을 숫자로 먼저 읽게 하지 않는다(pen 순서).
            Text(detail.bio!, style: AppTypography.body.copyWith(color: AppColors.body)),
          ],
          const _CardDivider(),
          _Facts(detail: detail),
          // 카드 안 섹션 사이는 전부 13 이다(pen `TORAs`).
          const SizedBox(height: _sectionGap),
          const _SectionLabel('성향'),
          for (var axis = 0; axis < _axisLabels.length; axis += 1)
            Padding(
              // 줄 사이에만 8 — 마지막 줄 뒤는 섹션 간격 13 하나만 남긴다(pen `TORAs`).
              padding: EdgeInsets.only(
                bottom: axis == _axisLabels.length - 1 ? 0 : AppSpacing.xs,
              ),
              child: TraitBar(
                leftLabel: _axisLabels[axis].left,
                rightLabel: _axisLabels[axis].right,
                value: axis < detail.survey.length ? detail.survey[axis] : 0,
              ),
            ),
          const SizedBox(height: _sectionGap),
          const _SectionLabel('외모 타입'),
          _LookType(detail: detail),
          const SizedBox(height: _sectionGap),
          _Tags(label: '관심사', values: detail.interests),
          _Tags(label: '특징', values: detail.myTraits),
          _Tags(label: '이상형 특징', values: detail.idealTraits),
          if (detail.idealNote != null) ...[
            const _SectionLabel('이런 사람이 좋아요'),
            Text(detail.idealNote!, style: AppTypography.body.copyWith(color: AppColors.body)),
          ],
        ],
      ),
    );
  }
}

/// 학교 · 학과 · 학번 한 줄(pen `TORAs`). 학과는 여기 있으므로 사실 칸에서는 뺀다.
class _SchoolLine extends StatelessWidget {
  const _SchoolLine({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    final profile = detail.profile;
    final parts = <String>[
      if (profile.university != null) profile.university!,
      if (profile.major != null) profile.major!,
      if (detail.studentNumber != null) '${detail.studentNumber}학번',
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        const Icon(AppIcons.graduationCap, size: 15, color: AppColors.muted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            parts.join(' '),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

/// 카드 안 구분선. 위아래 13 은 시안 실측값이다.
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 13),
      child: Divider(height: 1, thickness: 1, color: AppColors.hairlineSoft),
    );
  }
}

/// 키 · MBTI · 학번 · 종교 · 흡연 3열 2줄. 값이 없는 칸은 "—" 로 둔다.
/// 학과는 학교 줄에 있으므로 여기서 빠진다(2026-09-23 pen 대조).
class _Facts extends StatelessWidget {
  const _Facts({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    final facts = <({String label, String? value})>[
      (label: '키', value: detail.heightCm == null ? null : '${detail.heightCm}cm'),
      (label: 'MBTI', value: detail.mbti),
      (label: '학번', value: detail.studentNumber == null ? null : '${detail.studentNumber}학번'),
      (label: '종교', value: detail.religion.label),
      (label: '흡연', value: detail.isSmoker ? '흡연' : '비흡연'),
    ];
    // 두 줄 사이 10, 열 사이 8, 라벨-값 사이 2 는 pen `TORAs` 실측값이다.
    // 칸 폭(3열 균등, pen 91)은 최소값이다 — 글자를 키워(§11.2) 값이 칸을 넘으면 그 칸만 넓어지고
    // 뒤 칸은 다음 줄로 내려간다(백로그 31). 배율 1.0 에서는 지금처럼 3열 2줄이다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - AppSpacing.xs * 2) / 3;
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: 10,
          children: [
            for (final fact in facts)
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: cellWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fact.label,
                      style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fact.value ?? '—',
                      style: AppTypography.bodyStrong.copyWith(color: AppColors.ink),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 동물상 그림 + 동물상·인상 두 줄(pen `TORAs`).
class _LookType extends StatelessWidget {
  const _LookType({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(detail.animalType.iconAsset, width: 48, height: 48),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail.animalType.label,
              style: AppTypography.bodyStrong.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              detail.impressionType.label,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          // 고를 수 있는 칩이 아니라 읽기만 하는 칩이다 — `SelectChip`(높이 35·고르는 테두리)과 다르다.
          children: [for (final value in values) _TagChip(label: value)],
        ),
        const SizedBox(height: _sectionGap),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      // pen 칩 높이 30 은 최소값이다 — 글자를 키우면(§11.2) 칩이 따라 커진다(백로그 31).
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      // `alignment` 을 쓰면 폭 제한이 없는 `Wrap` 안에서 줄 폭을 통째로 먹어 칩이 세로로 쌓인다
      // (2026-09-26 실기기). 글자 높이만 가운데로 맞추고 폭은 글자만큼만 차지한다.
      child: Center(
        widthFactor: 1,
        child: Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.body)),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(text, style: AppTypography.labelSmall.copyWith(color: AppColors.muted)),
    );
  }
}
