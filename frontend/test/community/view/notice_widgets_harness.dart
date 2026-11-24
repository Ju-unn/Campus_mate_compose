import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 공지 부품 시험 틀 — 328 폭 한가운데에 놓는다(pen 본문 폭).
Future<void> pumpNoticePart(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: Center(child: SizedBox(width: 328, child: child))),
        ),
      ),
    );
