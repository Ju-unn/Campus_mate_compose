import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

/// 화면 문구는 `context.l10n.<키>` 로 읽는다(문구 파일 `lib/l10n/app_ko.arb`).
/// 에러 문구(`error*` 키)는 이 확장이 아니라 `core/l10n/error_text.dart` 의 `context.errorText(...)` 로만 읽는다.
/// 한국어 대체는 없다 — 위임자(`AppLocalizations.localizationsDelegates`)가 없는 곳에서 읽으면 바로 실패한다(`l10n.yaml` 의
/// `nullable-getter: false`). 앱은 `MaterialApp.router`(`main.dart`)가, 위젯 시험은 각 `MaterialApp` 이 위임자를 단다.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
