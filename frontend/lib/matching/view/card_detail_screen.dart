import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/common/widgets/card_action_bar.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/common/widgets/trait_bar.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
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
      appBar: AppBar(),
      bottomNavigationBar: detail == null
          ? null
          : CardActionBar(
              onReject: state.isSubmitting
                  ? null
                  : () => ref.read(provider.notifier).decide(CardDecision.reject),
              onAccept: state.isSubmitting
                  ? null
                  : () => ref.read(provider.notifier).decide(CardDecision.accept),
            ),
      body: SafeArea(
        child: switch (detail) {
          null when state.errorMessage != null => _Message(text: state.errorMessage!),
          null => const Center(child: CircularProgressIndicator()),
          _ => _DetailBody(detail: detail, errorMessage: state.errorMessage),
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

/// DESIGN.md §8.5 문항 표의 양 끝 라벨. 순서는 05-01 활동성 … 05-09 새로움이다.
const _axisLabels = <({String left, String right})>[
  (left: '집이 편해요', right: '밖이 좋아요'),
  (left: '낯을 많이 가려요', right: '금방 친해져요'),
  (left: '즉흥적이에요', right: '계획적이에요'),
  (left: '필요할 때만 해요', right: '자주 연락해요'),
  (left: '담백해요', right: '표현이 풍부해요'),
  (left: '거의 안 마셔요', right: '자주 즐겨요'),
  (left: '관심 없어요', right: '꾸준히 해요'),
  (left: '천천히요', right: '빠르게요'),
  (left: '익숙한 게 편해요', right: '새로운 걸 찾아요'),
];

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail, this.errorMessage});

  final CardDetail detail;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final profile = detail.profile;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _Avatar(url: profile.avatarUrl)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            profile.nameWithAge,
            // §8.1 이 토큰표 밖 드리프트로 못 박아 둔 값이다.
            style: AppTypography.title.copyWith(
              color: AppColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _Facts(detail: detail),
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel('성향'),
          for (var axis = 0; axis < _axisLabels.length; axis += 1)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: TraitBar(
                leftLabel: _axisLabels[axis].left,
                rightLabel: _axisLabels[axis].right,
                value: axis < detail.survey.length ? detail.survey[axis] : 0,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          _SectionLabel('외모 타입'),
          Row(
            children: [
              Image.asset(detail.animalType.iconAsset, width: 48),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${detail.animalType.label} · ${detail.impressionType.label}',
                style: AppTypography.body.copyWith(color: AppColors.body),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Tags(label: '관심사', values: detail.interests),
          _Tags(label: '특징', values: detail.myTraits),
          _Tags(label: '이상형 특징', values: detail.idealTraits),
          if (detail.bio != null) ...[
            _SectionLabel('자기소개'),
            Text(detail.bio!, style: AppTypography.body.copyWith(color: AppColors.body)),
            const SizedBox(height: AppSpacing.md),
          ],
          if (detail.idealNote != null) ...[
            _SectionLabel('이런 사람이 좋아요'),
            Text(detail.idealNote!, style: AppTypography.body.copyWith(color: AppColors.body)),
          ],
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(errorMessage!, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}

/// 학과 · 키 · MBTI · 학번 · 종교 · 흡연 6칸. 값이 없는 칸은 "—" 로 둔다.
class _Facts extends StatelessWidget {
  const _Facts({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    final facts = <String, String?>{
      '학과': detail.profile.major,
      '키': detail.heightCm == null ? null : '${detail.heightCm}cm',
      'MBTI': detail.mbti,
      '학번': detail.studentNumber == null ? null : '${detail.studentNumber}학번',
      '종교': detail.religion.label,
      '흡연': detail.isSmoker ? '흡연' : '비흡연',
    };
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        for (final fact in facts.entries)
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fact.key, style: AppTypography.caption.copyWith(color: AppColors.muted)),
                Text(
                  fact.value ?? '—',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
                ),
              ],
            ),
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
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            // 고르는 칩이 아니라 보여주기만 한다 — 조각 2 위젯을 선택 상태 없이 그대로 쓴다.
            for (final value in values)
              SelectChip(label: value, isSelected: false, onTap: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
      ],
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
      child: Text(text, style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceStrong),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(AppIcons.userRound, color: AppColors.disabled)
          : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
    );
  }
}
