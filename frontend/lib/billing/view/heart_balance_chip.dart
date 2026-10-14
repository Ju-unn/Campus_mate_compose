import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
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
/// 홈(`ihX4y`)과 나 탭 앱바(`hwVQB/MjtQA`, 2026-10-12 사용자 요청으로 "+" 켬 — pen 은 아직 "+" 없음) 모두 [showPlus] 를 켜서 쓴다.
/// "+" 를 누르면 할 일은 [onPlus] 가 정한다 — 두 화면 모두 `_openHeartStore` 로 하트 상점을 연다. null 이면 눌러도 아무 일도 없다.
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

  /// 잔액이 바뀔 때 새 숫자가 올라오기 시작하는 거리(대장 지시 10-14 — pen 에 모션 값은 없다).
  /// 아래 패딩(6)과 같아 칩 밖으로 삐져나가지 않는다.
  static const double _rise = 6;

  @override
  Widget build(BuildContext context) {
    final onPlus = this.onPlus;
    final instant = MediaQuery.disableAnimationsOf(context);
    // 패딩 [6,12,6,8] · gap 6 · 하트 24 · 숫자 18/700(렌더 높이 25) · plus 16 — 마스터 `sysyz`(토큰 밖 pen 리터럴).
    final padded = Padding(
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
            // 잔액이 바뀌면 새 숫자만 올라오고 옛 숫자는 사라진다. 사이 숫자를 세며 올라가지 않는다(카운트업 금지).
            // 처음 그릴 때(잔액을 읽은 직후)는 AnimatedSwitcher 가 효과 없이 그린다.
            // 옛 숫자 사라짐은 대장 지시 150ms 대신 토큰 press(120ms) — 모션은 토큰만 쓴다(CLAUDE.md §1-2).
            AnimatedSwitcher(
              duration: instant ? Duration.zero : AppMotion.standard,
              reverseDuration: instant ? Duration.zero : AppMotion.press,
              switchInCurve: AppMotion.standardCurve,
              switchOutCurve: AppMotion.pressCurve,
              layoutBuilder: _overlapAtStart,
              transitionBuilder: _riseIn,
              child: Text(
                _withCommas(balance),
                key: ValueKey(balance),
                style: AppTypography.subNavTitle.copyWith(
                  color: AppColors.ink,
                  height: 25 / 18,
                ),
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
    // 숫자가 바뀌면 칩 폭이 press 동안 따라간다(대장 지시). 처음 그릴 때는 늘이지 않는다.
    // 동작 줄이기면 AnimatedSize 를 아예 두지 않는다 — 시간 0 인 AnimatedSize 는 제 레이아웃 중에 다시 레이아웃을 걸어 오류가 난다.
    final content = instant
        ? padded
        : AnimatedSize(duration: AppMotion.press, curve: AppMotion.pressCurve, alignment: Alignment.centerLeft, child: padded);
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

  /// 옛 숫자와 새 숫자를 하트 바로 뒤(왼쪽)에 겹친다 — 폭이 다른 두 숫자가 가운데로 모이지 않게.
  static Widget _overlapAtStart(Widget? current, List<Widget> previous) => Stack(
    alignment: Alignment.centerLeft,
    children: [...previous, ?current],
  );

  /// 들어오는 숫자는 투명 · 아래 [_rise] 에서 제자리로, 나가는 숫자(되감기)는 제자리에서 투명해지기만 한다(transform · opacity 만).
  static Widget _riseIn(Widget child, Animation<double> animation) => FadeTransition(
    opacity: animation,
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, animation.status == AnimationStatus.reverse ? 0 : _rise * (1 - animation.value)),
        child: child,
      ),
      child: child,
    ),
  );

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
