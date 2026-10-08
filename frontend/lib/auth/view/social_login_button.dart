import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

/// 소셜 로그인 버튼 문구. 각 사 브랜드 규칙이 정한 글자라 바꾸지 않는다(대장 지시문 07).
abstract final class SocialLoginLabels {
  static const String kakao = '카카오 로그인';

  /// "Google" 한 단어만 쓰는 것은 Google 브랜드 규칙 위반이다.
  static const String google = 'Google 계정으로 로그인';

  /// 화면 읽기 이름.
  static const String kakaoSemantics = '카카오로 로그인';
  static const String googleSemantics = 'Google 계정으로 로그인';
}

/// 시작 화면의 소셜 로그인 버튼 한 개(카카오 · 구글, 애플은 자리만).
///
/// 높이 46 · 모서리 12 고정, 폭은 부모 칸 전체. [onPressed] 가 null 이면 비활성이고,
/// 비활성 · 로딩 · 눌림에서도 **브랜드 색을 바꾸지 않는다**(눌림은 잉크 효과만).
/// 로딩이면 레이블 자리에 스피너가 오고 심볼 · 로고는 그대로 남는다.
class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({required this.provider, required this.onPressed, this.isLoading = false, super.key});

  final SocialProvider provider;
  final VoidCallback? onPressed;
  final bool isLoading;

  static const double height = 46;

  /// 심볼 · 로고 칸(시험이 위치를 잰다).
  static const Key markKey = ValueKey('social-login-mark');

  @override
  Widget build(BuildContext context) {
    final brand = _Brand.of(provider);
    return Semantics(
      button: true,
      enabled: onPressed != null && !isLoading,
      label: brand.semanticsLabel,
      excludeSemantics: true,
      // 잉크가 화면 전체가 아니라 버튼 크기의 Material 위에 그려지게 버튼마다 Material 을 둔다(COMMON §4-2).
      child: Material(
        color: brand.container,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.socialButton), side: brand.stroke),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: brand.edgePadding),
              child: Center(child: _Content(brand: brand, isLoading: isLoading)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 심볼(로고) + 간격 + 레이블(또는 스피너)을 한 덩어리로 가운데 정렬한다.
class _Content extends StatelessWidget {
  const _Content({required this.brand, required this.isLoading});

  final _Brand brand;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(key: SocialLoginButton.markKey, dimension: brand.markSize, child: brand.mark),
        SizedBox(width: brand.markGap),
        // 글자 2.0배에서 칸이 모자라면 한 줄 그대로 비율을 유지하며 줄인다 — 잘리거나 말줄임되지 않는다.
        Flexible(
          child: isLoading
              ? _Spinner(color: brand.labelStyle.color!)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(brand.label, maxLines: 1, softWrap: false, style: brand.labelStyle),
                ),
        ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.color});

  static const double _size = 18;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _size,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

/// 공급자별 브랜드 규칙 값(대장 지시문 07 규칙표).
class _Brand {
  const _Brand({
    required this.container,
    required this.stroke,
    required this.mark,
    required this.markSize,
    required this.markGap,
    required this.label,
    required this.labelStyle,
    required this.semanticsLabel,
    required this.edgePadding,
  });

  factory _Brand.of(SocialProvider provider) {
    return switch (provider) {
      SocialProvider.kakao => _kakao,
      SocialProvider.google => _google,
      SocialProvider.apple => throw UnimplementedError('애플 로그인 버튼은 개발자 계정 승인 뒤 별도 PR 에서 그린다'),
    };
  }

  static final _Brand _kakao = _Brand(
    container: AppColors.kakaoContainer,
    stroke: BorderSide.none,
    mark: const CustomPaint(painter: _KakaoSymbolPainter()),
    markSize: 18,
    markGap: 8,
    label: SocialLoginLabels.kakao,
    // inherit: false — 앱 기본 글꼴 Pretendard(테마 textTheme)를 물려받지 않고 OS 기본 서체로 그린다.
    // 크기는 카카오 가이드 "레이블은 버튼 높이의 1/3 이하" → 46/3 ≈ 15.3 이하인 15.
    labelStyle: TextStyle(inherit: false, fontSize: 15, height: 1.2, color: AppColors.kakaoLabel),
    semanticsLabel: SocialLoginLabels.kakaoSemantics,
    // 카카오는 안쪽 좌우 padding 을 따로 두지 않고 심볼 + 레이블을 가운데 정렬한다(후속 지시문 13 B-2).
    edgePadding: 0,
  );

  static final _Brand _google = _Brand(
    container: AppColors.googleContainer,
    stroke: const BorderSide(color: AppColors.googleStroke, strokeAlign: BorderSide.strokeAlignInside),
    mark: Image.asset(
      'assets/images/google_g.png',
      width: 20,
      height: 20,
      // 자산이 없는 체크아웃(자산 PR 대기 중)에서도 화면이 깨지지 않게 빈 칸으로 둔다.
      errorBuilder: (context, error, stackTrace) => const SizedBox.square(dimension: 20),
    ),
    markSize: 20,
    markGap: 10,
    label: SocialLoginLabels.google,
    // Roboto 는 안드로이드 기본 서체라 글꼴 파일을 넣지 않는다. Medium 14/20.
    labelStyle: const TextStyle(
      inherit: false,
      fontFamily: 'Roboto',
      fontWeight: FontWeight.w500,
      fontSize: 14,
      height: 20 / 14,
      color: AppColors.googleLabel,
    ),
    semanticsLabel: SocialLoginLabels.googleSemantics,
    // 구글 규칙 "로고 앞 12 · 글자 뒤 12".
    edgePadding: 12,
  );

  final Color container;
  final BorderSide stroke;
  final Widget mark;
  final double markSize;
  final double markGap;
  final String label;
  final TextStyle labelStyle;
  final String semanticsLabel;

  /// 버튼 안쪽 좌우 여백.
  final double edgePadding;
}

/// 카카오 말풍선 심볼을 [size]×[size] 칸에 맞춰 만든다.
///
/// 카카오 로그인 공식 디자인 가이드의 심볼. 공식 SVG 의 `path` 를 그대로 옮기고
/// (원본 좌표 x 173.5~186.5, y 16.5~29.5 의 13×13 칸) 크기만 비율 유지로 키운다.
@visibleForTesting
Path kakaoSymbolPath(double size) {
  final path = Path()..moveTo(180.001, 16.5225);
  for (final segment in _kakaoSymbolSegments) {
    _addSegment(path, segment);
  }
  path.close();
  final scale = size / _kakaoSymbolBox;
  final matrix = Matrix4.diagonal3Values(scale, scale, 1)..translateByDouble(-173.5, -16.5, 0, 1);
  return path.transform(matrix.storage);
}

const double _kakaoSymbolBox = 13;

/// 좌표 6개는 cubicTo(C), 2개는 lineTo(L).
void _addSegment(Path path, List<double> p) {
  if (p.length == 2) {
    path.lineTo(p[0], p[1]);
    return;
  }
  path.cubicTo(p[0], p[1], p[2], p[3], p[4], p[5]);
}

/// 공식 SVG: `M180.001 16.5225C176.422 16.5225 … 180.001 16.5225Z`
const List<List<double>> _kakaoSymbolSegments = [
  [176.422, 16.5225, 173.522, 19.0037, 173.522, 22.0641],
  [173.522, 24.0312, 174.722, 25.7596, 176.529, 26.7423],
  [175.918, 29.2113],
  [175.895, 29.285, 175.913, 29.364, 175.962, 29.4184],
  [175.998, 29.457, 176.046, 29.478, 176.093, 29.478],
  [176.134, 29.478, 176.174, 29.464, 176.208, 29.4341],
  [178.834, 27.5144],
  [179.212, 27.5723, 179.601, 27.6039, 179.999, 27.6039],
  [183.577, 27.6039, 186.478, 25.1226, 186.478, 22.0623],
  [186.478, 19.002, 183.578, 16.5225, 180.001, 16.5225],
];

class _KakaoSymbolPainter extends CustomPainter {
  const _KakaoSymbolPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(kakaoSymbolPath(size.shortestSide), Paint()..color = AppColors.kakaoSymbol);
  }

  @override
  bool shouldRepaint(_KakaoSymbolPainter oldDelegate) => false;
}
