import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/l10n/app_localizations.dart';

/// 하단 내비 탭의 글자(pen `Migf0`, 문구 파일 ARB). 두 내비([AppBottomNav] · 유리 알약)가 같은 글자를 쓴다.
extension AppTabText on AppTab {
  String label(AppLocalizations l10n) => switch (this) {
        AppTab.main => l10n.commonBottomNavMain,
        AppTab.today => l10n.commonBottomNavToday,
        AppTab.community => l10n.commonBottomNavCommunity,
        AppTab.chat => l10n.commonBottomNavChat,
        AppTab.me => l10n.commonBottomNavMe,
      };
}
