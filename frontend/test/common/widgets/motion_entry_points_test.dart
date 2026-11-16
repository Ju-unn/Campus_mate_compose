import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 스낵바 · 토스트 · 팝업 · 바텀시트의 움직임은 common/widgets 의 띄우기 함수 한 곳이 정한다(사용자 2026-11-16).
/// 화면이 Flutter 함수를 직접 부르면 그 화면만 기본 움직임으로 돌아가므로, lib 안에서 부르는 자리를 지킨다.
void main() {
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => (path: file.path.replaceAll(r'\', '/').substring('lib/'.length), lines: file.readAsLinesSync()))
      .toList();

  /// [pattern] 을 주석이 아닌 줄에서 부르는 파일 가운데 [allowed] 밖의 것.
  List<String> callersOutside(RegExp pattern, Set<String> allowed) => [
        for (final source in sources)
          if (!allowed.contains(source.path) &&
              source.lines.any((line) => !line.trimLeft().startsWith('//') && pattern.hasMatch(line)))
            source.path,
      ];

  test('SnackBar 는 app_snack_bar.dart 로만 띄운다(스낵바는 아래에서 올라오고, 토스트 알약은 제자리 fade)', () {
    expect(callersOutside(RegExp(r'\.showSnackBar\('), {'common/widgets/app_snack_bar.dart'}), isEmpty);
  });

  test('바텀시트는 app_bottom_sheet.dart 로만 띄운다', () {
    expect(callersOutside(RegExp(r'\bshowModalBottomSheet\b'), {'common/widgets/app_bottom_sheet.dart'}), isEmpty);
    // 주소로 여는 20b 시트는 경로를 직접 만든다 — 같은 움직임 값을 쓰는지만 본다.
    for (final path in callersOutside(RegExp(r'\bModalBottomSheetRoute\b'), {})) {
      final text = sources.firstWhere((source) => source.path == path).lines.join('\n');
      expect(text, contains('sheetAnimationStyle: appSheetAnimationStyle('), reason: path);
    }
  });

  test('팝업은 app_dialog_route.dart 로만 띄운다(사진 확대 보기는 투명도만 바뀌는 별도 규칙 — DESIGN §7)', () {
    expect(
      callersOutside(
        RegExp(r'\b(showDialog|showGeneralDialog|showAdaptiveDialog|showCupertinoDialog|showCupertinoModalPopup)\b'),
        {'common/widgets/app_dialog_route.dart', 'me/view/photo_zoom_viewer.dart'},
      ),
      isEmpty,
    );
  });
}
