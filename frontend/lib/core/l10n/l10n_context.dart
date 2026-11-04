import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter/widgets.dart';

/// 위임자가 없는 곳(기존 위젯 시험의 맨 `MaterialApp`)에서 쓰는 한국어 문구. 앱 본체는 `MaterialApp.router` 가 위임자를 켠다.
final AppLocalizations _koreanFallback = AppLocalizationsKo();

/// 화면 문구는 `context.l10n.<키>` 로 읽는다(문구 파일 `lib/l10n/app_ko.arb`).
/// 에러 문구(`error*` 키)는 이 확장이 아니라 `core/l10n/error_text.dart` 의 `context.errorText(...)` 로만 읽는다.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this) ?? _koreanFallback;
}
