import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/instagram_link.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 9b-1 이벤트(출시 예정, pen `q2mpPW`, 대장 전달 값 10-15). 홈 6칸 그리드의 이벤트 칸이 push 로 연다 — 하단 내비 없음.
/// 마스코트 · 제목 · 설명 · 인스타그램 버튼을 묶어 앱바 아래 칸 가운데에 두고 아래로 48 치우친다(03b 와 같은 규칙).
/// 이벤트가 생기면 본문을 카드 목록으로 넓힌다(지금은 만들지 않는다).
class EventComingScreen extends ConsumerStatefulWidget {
  const EventComingScreen({super.key});

  @override
  ConsumerState<EventComingScreen> createState() => _EventComingScreenState();
}

class _EventComingScreenState extends ConsumerState<EventComingScreen> with MeToastHost<EventComingScreen> {
  bool _opening = false;

  /// 기기 앱 · 브라우저로 인스타그램을 연다(홈 `_openExternal` 과 같은 규칙). 열지 못하면 실패 안내를 띄운다.
  Future<void> _openInstagram() async {
    if (_opening) return; // 여는 호출이 끝나기 전에 다시 눌러도 두 번 열지 않는다
    _opening = true;
    var opened = false;
    try {
      opened = await ref.read(openUrlProvider)(instagramLink);
    } catch (_) {
      // 기기 쪽 오류 — 아래에서 안내한다.
    } finally {
      _opening = false;
    }
    if (!opened) {
      showTimedToast(
        AppToast(
          leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
          label: const UnknownFailure().toDisplayMessage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: const EditAppBar(title: '이벤트'),
      body: SafeArea(
        top: false,
        child: MeToastLayer(
          toast: timedToast,
          // 작은 화면 · 큰 글씨에서 묶음이 칸보다 커지면 가운데를 버리고 스크롤한다.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
                  child: Center(child: _Body(onInstagram: _openInstagram)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 마스코트 120 → 8 → 제목 20/700 → 8 → 설명 14/400 body → 16 → 인스타 버튼. 폭 312(= 360 − 24 × 2).
/// 제목 ↔ 설명 8 · 제목 줄높이(title 토큰 1.4)는 대장 값에 없어 정한 값이다(pen 확인 대상).
class _Body extends StatelessWidget {
  const _Body({required this.onInstagram});

  final VoidCallback onInstagram;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset(
            'assets/images/mascot-male-waiting.png',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '이벤트가 곧 열려요',
          textAlign: TextAlign.center,
          style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '새로운 이벤트가 준비되는 대로 여기서 알려 드릴게요. 인스타그램에서도 소식을 만나 보세요.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.body),
        ),
        const SizedBox(height: AppSpacing.md),
        _InstagramButton(onPressed: onInstagram),
      ],
    );
  }
}

/// "인스타그램 보러 가기"(pen `button-secondary` 모양 — 채움 #E5E5E5 · 모서리 14 · 높이 52, 가운데 [로고 24 · 8 · 16/700 ink]).
/// 공용 [AppButton] 은 앞 그림 칸이 없어 같은 값으로 여기 둔다 — 자기 Material 이 있어 잉크가 제자리다.
class _InstagramButton extends StatelessWidget {
  const _InstagramButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryDisabled,
        foregroundColor: AppColors.ink,
        elevation: 0,
        // 52 는 최소 높이다 — 글자를 키우면 늘어난다.
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 공식 로고 모양 · 색 그대로(늘이거나 물들이지 않는다). 옆 글자가 이름을 말하므로 낭독기에는 읽지 않는다.
          Image.asset(
            'assets/images/brand-instagram-v1.webp',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: Text('인스타그램 보러 가기', style: AppTypography.button.copyWith(color: AppColors.ink))),
        ],
      ),
    );
  }
}
