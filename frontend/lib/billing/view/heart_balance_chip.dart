import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 재화 하트(DESIGN §5.4 — Lucide 가 아니라 이미지). pen `l4vdk`.
const String _heartAsset = 'assets/images/heart-flat-vector-v3.png';

/// 내 하트 잔액 칩(pen 마스터 `sysyz` HeartBalanceChip). 잔액은 서버 값(`MyProfile.heartBalance`)을 읽는다 —
/// 앱에 숫자를 두지 않는다. 읽는 중 · 실패에는 칩을 숨긴다(pen 에 없는 상태 — 대장 추천, 값이 오면 보인다).
///
/// 나 탭 앱바(`hwVQB/MjtQA`)는 "+" 없이, 홈(`ihX4y`)은 [showPlus] 를 켜서 쓴다. "+" 를 누르면 할 일은 [onPlus] 가 정한다 —
/// 홈은 `_openHeartStore` 로 하트 상점을 연다. null 이면 눌러도 아무 일도 없다.
class HeartBalanceChip extends ConsumerWidget {
  const HeartBalanceChip({this.showPlus = false, this.onPlus, super.key});

  final bool showPlus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(
      myProfileProvider.select(
        (profile) => profile.value?.when(
          onSuccess: (value) => value.heartBalance,
          onFailure: (_) => null,
        ),
      ),
    );
    if (balance == null) return const SizedBox.shrink();
    return HeartBalanceChipView(
      balance: balance,
      showPlus: showPlus,
      onPlus: onPlus,
    );
  }
}

/// 칩 그림 하나 — 값만 받는다. 마스터 `sysyz` 는 내용 폭(fit_content)이고 인스턴스는 높이 44 로 쓴다.
class HeartBalanceChipView extends StatelessWidget {
  const HeartBalanceChipView({
    required this.balance,
    this.showPlus = false,
    this.onPlus,
    super.key,
  }) : assert(!showPlus || onPlus != null, '"+" 를 켜면 누를 때 할 일(onPlus)도 줘야 한다');

  final int balance;
  final bool showPlus;
  final VoidCallback? onPlus;

  /// pen 인스턴스 높이 — 눈에 보이는 분홍 띠와 눌림 효과가 그려지는 칸.
  static const double _height = 44;

  /// 누를 수 있을 때의 눌림 칸 높이(안드로이드 터치 영역 48). 띠(44)는 이 안 가운데에 그대로 두고 위아래 2 는 투명하다.
  static const double _tapHeight = 48;

  /// 숫자 줄 높이 25 × 배율이 칸 32 안에 드는 가장 큰 배율(25 × 1.2 = 30).
  static const double _maxTextScale = 1.2;

  @override
  Widget build(BuildContext context) {
    final onPlus = this.onPlus;
    // 패딩 [6,12,6,8] · gap 6 · 하트 24 · 숫자 18/700(렌더 높이 25) · plus 16 — 마스터 `sysyz`(토큰 밖 pen 리터럴).
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      // 높이 44 가 고정이라 글자 배율은 숫자가 칸(44 − 위아래 12)에 들어가는 [_maxTextScale] 까지만 따른다 — 앱바 제목에 자리도 남긴다.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTextScale,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              _heartAsset,
              width: 24,
              height: 24,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 6),
            Text(
              _withCommas(balance),
              style: AppTypography.subNavTitle.copyWith(
                color: AppColors.ink,
                height: 25 / 18,
              ),
            ),
            if (showPlus) ...[
              const SizedBox(width: 6),
              const Icon(AppIcons.plus, size: 16, color: AppColors.primaryText),
            ],
          ],
        ),
      ),
    );
    final radius = BorderRadius.circular(AppRadius.pill);
    final tappable = showPlus && onPlus != null;
    // 높이 44 는 눈에 보이는 분홍 띠와 누름 칸 자체의 높이다(바깥 상자만 44 면 띠가 37 로 줄고 누름 칸도 44 미만이 된다).
    // 눌림 효과를 그릴 Material 이 모양 안에 있어야 한다(COMMON §4-2).
    final shape = Material(
      color: AppColors.primaryWash,
      borderRadius: radius,
      child: SizedBox(
        height: _height,
        child: tappable
            ? InkWell(
                borderRadius: radius,
                onTap: onPlus,
                child: Center(widthFactor: 1, child: content),
              )
            : Center(widthFactor: 1, child: content),
      ),
    );
    return Semantics(
      label: '보유 하트 $balance개',
      hint: tappable ? '하트 충전' : null,
      button: tappable,
      excludeSemantics: true,
      onTap: showPlus ? onPlus : null,
      // 눌림 칸만 48 로 넓힌다 — 띠의 눌림 효과(InkWell)는 띠 안(44)에서 그려지고, 위아래 2 는 투명한 opaque 칸이 받는다.
      child: tappable
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPlus,
              child: SizedBox(height: _tapHeight, child: Center(widthFactor: 1, child: shape)),
            )
          : shape,
    );
  }

  /// 1,250 처럼 천 단위마다 쉼표(pen 칩 예시는 "320" 뿐 — 쉼표는 대장 추천).
  static String _withCommas(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
