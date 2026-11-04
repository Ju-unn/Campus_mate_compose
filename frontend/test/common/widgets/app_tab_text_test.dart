import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_tab_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('하단 내비 탭 글자는 시안 순서 그대로다 — 글자는 문구 파일(ARB)에서 온다', () {
    final l10n = AppLocalizationsKo();

    expect([for (final tab in AppTab.values) tab.label(l10n)], ['메인', '오늘', '커뮤니티', '대화', '나']);
  });
}
