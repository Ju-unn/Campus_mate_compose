import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<BuildContext> pump(WidgetTester tester, {required bool withDelegates}) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: withDelegates ? AppLocalizations.localizationsDelegates : null,
        supportedLocales: withDelegates ? AppLocalizations.supportedLocales : const [Locale('en', 'US')],
        home: Builder(builder: (context) {
          captured = context;
          return const SizedBox();
        }),
      ),
    );
    return captured;
  }

  testWidgets('앱처럼 위임자를 켜면 context.l10n 은 그 위임자가 읽어 온 한국어 문구다', (tester) async {
    final context = await pump(tester, withDelegates: true);

    expect(context.l10n, same(AppLocalizations.of(context)));
    expect(context.l10n.commonRetry, '다시 시도');
  });

  testWidgets('위임자가 없는 MaterialApp(기존 위젯 시험)에서는 한국어 고정 문구로 떨어진다', (tester) async {
    final context = await pump(tester, withDelegates: false);

    expect(AppLocalizations.of(context), isNull);
    expect(context.l10n.commonRetry, '다시 시도');
  });

  testWidgets('기기 언어가 영어여도 지원 언어가 한국어 하나라 한국어로 떨어진다', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          captured = context;
          return const SizedBox();
        }),
      ),
    );

    expect(Localizations.localeOf(captured), const Locale('ko'));
    expect(captured.l10n.commonRetry, '다시 시도');
  });
}
