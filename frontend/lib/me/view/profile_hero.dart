import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:flutter/material.dart';

/// 화면 15 히어로(pen 마스터 `l8p6X` "ProfileHero", 328×360) — 아바타 그림 위에 보기 칩 · 인증 배지(위)와 이름 묶음(아래).
/// 이름 묶음 오른쪽 아래 "다시 만들기 · 10" 알약(`R5Quru`)이 15b 시트를 연다.
class ProfileHero extends StatelessWidget {
  const ProfileHero({required this.profile, required this.onRegenerate, super.key});

  final MyProfile profile;

  /// null 이면 15-2 비활성 알약(`EAqjZ`) — 만드는 중이라 눌러도 아무 일 없다.
  final VoidCallback? onRegenerate;

  /// pen 높이 360 은 최소값이다 — 글자를 키워 이름 묶음이 커지면 히어로가 늘어난다(DESIGN §11.2).
  static const double _minHeight = 360;

  /// 스크림 `gyzqh` 위 끝(y150). 아래 끝은 히어로 끝 — 히어로가 늘면 같이 늘어난다.
  static const double _scrimTop = 150;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minHeight),
        // passthrough — 최소 높이를 안쪽 Column 까지 넘겨야 space_between 이 칩과 이름 묶음을 위아래 끝으로 민다.
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(child: _Picture(url: profile.avatarUrl)),
            const Positioned(top: _scrimTop, left: 0, right: 0, bottom: 0, child: _Scrim()),
            Padding(
              // `l8p6X` 패딩 [16,16,20,16]. 아래 20 중 10 은 알약 누름 칸이 쓴다([_RegeneratePill.tapExtension]).
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                20 - _RegeneratePill.tapExtension,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Row `dd4Jv` — space_between · 가운데 맞춤: 보기 칩 왼쪽, 인증 배지 오른쪽.
                  // 글자를 키워 폭이 모자라면 칩 글자가 줄을 바꾼다. 사이 8 은 pen 에 없는 최소 간격(맞닿지 않게).
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: _PillBadge.viewChip()),
                      SizedBox(width: AppSpacing.xs),
                      _VerifiedBadge(),
                    ],
                  ),
                  _Identity(profile: profile, onRegenerate: onRegenerate),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 아바타 그림(cover — 꽉 채워 자른다). 아바타가 없으면 같은 크기 surface-soft 빈 칸(N9, 옛 15 와 같은 규칙).
/// 그림은 decoration 으로 깐다 — Image 위젯은 그림 비율로 제 높이를 주장한다.
class _Picture extends StatelessWidget {
  const _Picture({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return Semantics(
      image: url != null,
      label: url == null ? null : '내 AI 아바타',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: url == null ? AppColors.surfaceSoft : null,
          image: url == null ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// 스크림 `gyzqh` — ink 위 → 아래 선형(α 0 → 0.45 → 0.65 → 0.85). 흰 이름 글자가 밝은 그림 · 빈 칸 위에서도 읽힌다.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [for (final alpha in [0.0, 0.45, 0.65, 0.85]) AppColors.surfaceInk.withValues(alpha: alpha)],
          stops: const [0, 0.35, 0.6, 1],
        ),
      ),
    );
  }
}

/// Badge `XPRBv` 알약 — 패딩 [6,10](토큰 밖 리터럴) · 모서리 pill · 아이콘 → 4 → 글자(600, 줄높이 1.5).
/// 두 인스턴스가 색 · 아이콘 크기 · 글자 크기만 덮어쓴다.
class _PillBadge extends StatelessWidget {
  /// 보기 칩 `h9sFd` — #222222 **불투명**(N15) · eye 14 · "상대에게 이렇게 보여요" 13 흰색.
  const _PillBadge.viewChip()
      : icon = AppIcons.eye,
        iconSize = 14,
        label = '상대에게 이렇게 보여요',
        fontSize = 13,
        background = AppColors.surfaceInk,
        foreground = AppColors.onInk;

  final IconData icon;
  final double iconSize;
  final String label;
  final double fontSize;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: foreground),
            const SizedBox(width: AppSpacing.xxs),
            // 13 · 12 는 타입 토큰 사이 값이라 labelSmall(14/600)에 크기만 덮어쓴다.
            Flexible(
              child: Text(
                label,
                style: AppTypography.labelSmall.copyWith(fontSize: fontSize, height: 1.5, color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 학생 인증 배지 `EQjrL`(3D) — 흰 알약 · 그림자 · [6,10] · 3D badge-check 18 → 4 → "학생 인증" 11/600 ink.
/// 늘 보인다 — `GET /me/profile` 은 인증된 사람만 닿는다.
class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  /// pen `EQjrL` 그림자 #34223A24 (0,2) blur 8. 그림자 토큰과 값이 달라(AppElevation.badge 는 #6F40551A blur 10) 리터럴로 둔다.
  static const List<BoxShadow> _shadow = [BoxShadow(color: Color(0x2434223A), offset: Offset(0, 2), blurRadius: 8)];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: _shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon3d(AppIcon3d.badgeCheck, size: 18),
            const SizedBox(width: AppSpacing.xxs),
            // 11/600 — 줄높이는 pen 에 없어 보기 칩(Badge `XPRBv`)과 같은 1.5. 높이는 아이콘 18 이 정한다.
            Text('학생 인증', style: AppTypography.labelSmall.copyWith(fontSize: 11, height: 1.5, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

/// Identity Block `IUcwD` — 이름 줄(`fXWlF`) → 2 → 학교 줄(`p2UWV`).
class _Identity extends StatelessWidget {
  const _Identity({required this.profile, required this.onRegenerate});

  final MyProfile profile;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final (age, major) = (profile.age, profile.major);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 이름 줄 `fXWlF`(gap 8) — 인증 배지가 위쪽 줄로 옮겨 가 닉네임 하나만 남았다.
        // 닉네임 `CM0QK` 24/700 lh1.35 = headline 토큰. 길면 줄을 바꾼다 — 말줄임은 학교 줄만(N7).
        Text(
          age == null ? profile.nickname : '${profile.nickname}, $age',
          style: AppTypography.headline.copyWith(color: AppColors.onInk),
        ),
        // Name Copy gap 2(토큰 밖 리터럴).
        const SizedBox(height: 2),
        _SchoolRow(school: major == null ? profile.university : '${profile.university} · $major', onRegenerate: onRegenerate),
      ],
    );
  }
}

/// 학교 줄 `p2UWV` — 학교 칸(fill, 한 줄 말줄임 N7) → 12 → 알약.
class _SchoolRow extends StatelessWidget {
  const _SchoolRow({required this.school, required this.onRegenerate});

  final String school;
  final VoidCallback? onRegenerate;

  /// 알약은 줄 폭의 3/4 까지다. 글자를 키워 그보다 넓어지면 알약 글자가 줄을 바꾸고, 학교 칸은 나머지(1/4 − 12)에서
  /// 말줄임한다 — Pretendard 로 배율 2.0 까지 알약이 한 줄이다(1.0 에서 129 · 44%, 2.0 에서 약 218 · 74%).
  static const double _pillMaxShare = 0.75;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        // 위 맞춤 — 알약 누름 칸이 아래로만 10 늘어서(가운데 맞춤이면 학교 글자가 5 내려간다) 학교 칸이 알약 몸통 높이
        // 안에서 스스로 가운데를 잡는다.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _RegeneratePill.height),
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: Text(
                  school,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // `C9JEi` 14/400 lh1.55 = bodySmall 토큰.
                  style: AppTypography.bodySmall.copyWith(color: AppColors.onInk),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * _pillMaxShare),
            child: _RegeneratePill(onTap: onRegenerate),
          ),
        ],
      ),
    );
  }
}

/// "다시 만들기 · 10" 알약 `R5Quru` — 높이 34 · 흰 알약 · 좌우 10 · 하트 16 → 4 → 13/600 primary-text.
/// 글자의 10 은 서버 `avatarRegenCost` 가 아니라 pen 고정이다(D6 — 무료 차례에도 같다. 실제 값은 15b 시트가 읽는다).
///
/// 누름 칸은 44(N7)인데 pen 몸통은 34 다. 칸을 위로 늘리면 이름 줄이 밀리므로 **아래(히어로 아래 여백 20 쪽)로만 10**
/// 늘린다 — 히어로가 그만큼 아래 여백을 덜 둔다. 몸통 밖 10 은 [GestureDetector] 가 받고, 몸통 안은 눌림 효과를 그리는
/// [InkWell] 이 받는다(안쪽이 이겨 한 번만 불린다).
class _RegeneratePill extends StatelessWidget {
  const _RegeneratePill({required this.onTap});

  final VoidCallback? onTap;

  static const double height = 34;
  static const double tapExtension = 10;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    const shape = StadiumBorder();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 화면 읽기는 아래 버튼 하나만 — 이 칸이 따로 누를 곳으로 잡히면 두 번 멈춘다.
      excludeFromSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: tapExtension),
        // 하트 라벨과 글자를 버튼 하나로 합친다 — "하트, 다시 만들기 · 10, 버튼" 을 한 번에 읽는다(15b 검토 권고 1).
        child: MergeSemantics(
          child: Semantics(
            button: true,
            enabled: enabled,
            // 15-2 `EAqjZ`: #E5E5E5 · 하트 숨김 · 글자 #929292.
            child: Material(
              color: enabled ? AppColors.canvas : AppColors.primaryDisabled,
              shape: shape,
              // 히어로는 스크롤 안이라 눌림 효과를 알약 크기 Material 위에 그린다(COMMON §4-2).
              child: InkWell(
                customBorder: shape,
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: height),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (enabled) ...[const _HeartGlyph(), const SizedBox(width: AppSpacing.xxs)],
                        Flexible(
                          child: Text(
                            '다시 만들기 · 10',
                            textAlign: TextAlign.center,
                            style: AppTypography.labelSmall.copyWith(
                              fontSize: 13,
                              height: 1.5,
                              color: enabled ? AppColors.primaryText : AppColors.disabled,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 재화 하트 `yhwPU`(Heart Value Icon `l4vdk` 16) — 흰 바탕이라 원본 v3(DESIGN §8.3 · §8.10).
/// 재화 글리프는 "하트" 로 읽는다(CLAUDE.md §7) — 알약의 [MergeSemantics] 가 버튼 라벨에 합친다.
class _HeartGlyph extends StatelessWidget {
  const _HeartGlyph();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '하트',
      child: Image.asset('assets/images/heart-flat-vector-v3.png', width: 16, height: 16, excludeFromSemantics: true),
    );
  }
}
