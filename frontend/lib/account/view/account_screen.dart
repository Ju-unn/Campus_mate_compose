import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/viewmodel/account_info_provider.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 16e 계정(pen `i3WGAa`). 16 "계정" 에서 들어온다. 값은 보기만 한다 — 카톡 줄만 16e-1 로 가고, 저장하고 돌아오면 다시 읽는다(T3).
/// 불러오는 중 · 실패는 pen 에 없어 화면 15 와 같은 모양을 쓴다(사용자 결정 2026-09-27).
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  /// DESIGN §9 16e 확정 문구(pen `FLwiN`).
  static const privacyNote = '실명과 출생연도는 학생증 대조와 운영 확인에만 쓰여요. 다른 사용자에게는 닉네임만 보여요.';

  /// 값이 아직 없을 때(pen 에 없는 상태, 대장 결정 2026-09-28).
  static const emptyValue = '—';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // 설정 화면과 같은 방식(pen `dQNBh`).
      appBar: AppBar(title: Text('계정', style: AppTypography.navTitle)),
      body: SafeArea(
        child: ref.watch(accountInfoProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _LoadError(onRetry: () => ref.invalidate(accountInfoProvider)),
              data: (result) => result.when(
                onSuccess: (info) => _AccountContent(
                  info: info,
                  // 16e-1 은 저장하면 true 를 들고 닫힌다 — 그때만 다시 읽는다(채팅방 14f "변경" 과 같다, 대장 결정 2026-09-28).
                  onKakaoIdTap: () async {
                    final saved = await context.push<bool>(AppRoutes.kakaoIdSettings);
                    if (saved == true && context.mounted) ref.invalidate(accountInfoProvider);
                  },
                ),
                onFailure: (_) => _LoadError(onRetry: () => ref.invalidate(accountInfoProvider)),
              ),
            ),
      ),
    );
  }
}

/// 불러오기 실패. pen 에 없는 상태라 화면 15(`my_profile_screen.dart` `_LoadError`)와 같은 모양을 쓴다.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('잠시 뒤 다시 시도해 주세요', style: AppTypography.body.copyWith(color: AppColors.body)),
          AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
        ],
      ),
    );
  }
}

/// 본문(pen `n8lZI`) — 좌우 md · 위 sm · 아래 lg, 구역 사이 20, 구역 머리와 카드 사이 xs.
class _AccountContent extends StatelessWidget {
  const _AccountContent({required this.info, required this.onKakaoIdTap});

  final AccountInfo info;
  final VoidCallback onKakaoIdTap;

  /// pen 구역 사이 간격 20 은 간격 토큰(md 16 · lg 24) 사이 값이다(block_list_screen `_gap` 과 같은 이유).
  static const double _sectionGap = 20;

  /// "학생 인증" 값(항상 "인증 완료") 전용 — 기본 값 스타일과 달리 굵고 primary-text.
  static final _verifiedStyle =
      AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryText);

  @override
  Widget build(BuildContext context) {
    // 계획서는 `ListView` 를 쓰라 했지만(brief), 구역 5개뿐인 고정 목록이라
    // `SingleChildScrollView`+`Column` 으로 바꿨다 — `ListView` 는 느긋한 sliver 라
    // 테스트 화면(800x600, 배율 안 키움)에서 "가입 정보" 아래 줄이 아예 안 그려져
    // `find.text` 로 못 찾았다(위젯 트리에 없음, 잘림이 아니다). 스크롤이면 결과는 같다.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader('로그인 정보'),
          const SizedBox(height: AppSpacing.xs),
          _InfoCard(rows: [
            _InfoRow(icon: AppIcon3d.mail, label: '학교 이메일', value: info.email),
            _InfoRow(icon: AppIcon3d.badgeCheck, label: '학생 인증', value: '인증 완료', valueStyle: _verifiedStyle),
          ]),
          const SizedBox(height: _sectionGap),
          const _SectionHeader('본인 확인 정보'),
          const SizedBox(height: AppSpacing.xs),
          _InfoCard(rows: [
            _InfoRow(icon: AppIcon3d.userRound, label: '실명', value: info.realName ?? AccountScreen.emptyValue),
            _InfoRow(
              icon: AppIcon3d.calendar,
              label: '출생연도',
              value: info.birthYear?.toString() ?? AccountScreen.emptyValue,
            ),
            _InfoRow(icon: AppIcon3d.graduationCap, label: '학교', value: info.university, schoolLogo: true),
          ]),
          const SizedBox(height: _sectionGap),
          const _PrivacyNote(),
          const SizedBox(height: _sectionGap),
          const _SectionHeader('연락처 공개 정보'),
          const SizedBox(height: AppSpacing.xs),
          _InfoCard(rows: [
            _InfoRow(
              icon: AppIcon3d.chat,
              label: '카카오톡 아이디',
              value: info.kakaoId ?? AccountScreen.emptyValue,
              onTap: onKakaoIdTap,
            ),
          ]),
          const SizedBox(height: _sectionGap),
          const _SectionHeader('가입 정보'),
          const SizedBox(height: AppSpacing.xs),
          _InfoCard(rows: [
            _InfoRow(icon: AppIcon3d.calendarCheck, label: '가입일', value: _joinedAtLabel(info.joinedAt)),
          ]),
        ],
      ),
    );
  }

  /// 한국 날짜 — 기기 시간대에 끌려가지 않게 UTC+9 로 고정해서 계산한다.
  static String _joinedAtLabel(DateTime joinedAt) {
    final kst = joinedAt.toUtc().add(const Duration(hours: 9));
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${kst.year}.${twoDigits(kst.month)}.${twoDigits(kst.day)}';
  }
}

/// 구역 머리(pen `GsxGU` 등) — 14/700 muted, 줄높이 속성 없음이라 20/14 로 맞춘다.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.muted, height: 20 / 14),
    );
  }
}

/// 카드(pen `DRNO6` · `WWHip` · `htOK0` · `CNJKy`). 본보기는 `block_list_screen.dart` `_BlockedCard`.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceSoft,
      shape: RoundedRectangleBorder(
        // pen 모서리 12 는 라운드 토큰(sm 8 · md 14) 사이 값이다(`_BlockedCard` 와 같은 이유).
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// 정보 줄. [onTap] 을 주면(카톡 줄) 끝에 셰브런이 붙고, 잉크는 카드 [Material] 에 그린다.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
    this.schoolLogo = false,
    this.onTap,
  });

  final AppIcon3d icon;
  final String label;
  final String value;

  /// 기본 값 스타일과 다를 때만 준다("학생 인증" 의 "인증 완료" 는 굵게 primary-text).
  final TextStyle? valueStyle;

  /// 학교 줄(pen `SQQa9` · `FNU1J` School Symbol) — 값 앞에 학교 로고를 붙인다. 로고가 없으면 글자만.
  final bool schoolLogo;

  final VoidCallback? onTap;

  /// pen 학교 이메일 줄의 3D 아이콘 `huZA9` 22×22 — 다른 줄도 같은 줄 틀(pen 인스턴스)이라 같은 크기로 둔다.
  static const double _iconSize = 22;

  /// pen 높이 52 는 최소값이다 — 글자를 키우면 줄이 늘어난다(고정 높이면 조용히 잘린다).
  static const double _minHeight = 52;

  /// pen 좌우 여백 14 는 간격 토큰(sm 12 · md 16) 사이 값이다.
  static const double _horizontalPadding = 14;

  @override
  Widget build(BuildContext context) {
    final style = valueStyle ?? AppTypography.bodySmall.copyWith(color: AppColors.muted);
    final valueText = schoolLogo
        // SchoolLabel 은 제 폭만큼만 차지한다 — 오른쪽 끝에 붙이려고 Align 으로 민다.
        ? Align(alignment: Alignment.centerRight, child: SchoolLabel(value, style: style, textAlign: TextAlign.end))
        : Text(value, textAlign: TextAlign.end, style: style);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minHeight),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        decoration: const BoxDecoration(
          // 모든 줄 아래 — 마지막 줄에도 있다(pen).
          border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Icon3d(icon, size: _iconSize),
              const SizedBox(width: AppSpacing.sm),
              // 라벨은 줄 폭의 절반까지만 — 글자를 키우면 라벨이 값 칸을 다 먹어 값이 조용히 잘린다
              // (2.0배 "카카오톡 아이디" 가 값 칸을 1.3px 로 만들었다). 1.0배 라벨은 절반보다 짧다.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
                child: Text(label, style: AppTypography.body.copyWith(color: AppColors.ink, height: 23 / 16)),
              ),
              const SizedBox(width: AppSpacing.sm),
              // pen 은 라벨 fill · 값 hug — 값이 남은 폭을 다 받고 오른쪽 끝에 붙는다. 길면 줄바꿈만 한다(조용한 잘림 금지).
              Expanded(child: valueText),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.sm),
                const Icon(AppIcons.chevronRight, size: 18, color: AppColors.muted),
              ],
            ],
          ),
        ),
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// 안내문(pen `o1G2A` / `FLwiN`) — 본인 확인 정보 카드 바로 아래. `InfoNote` 는 아이콘·모서리 14 가 달라 쓰지 않는다.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  /// pen 여백 14 는 간격 토큰(sm 12 · md 16) 사이 값이다.
  static const double _padding = 14;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        // pen 모서리 12 는 라운드 토큰(sm 8 · md 14) 사이 값이다.
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        AccountScreen.privacyNote,
        style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 1.5),
      ),
    );
  }
}
