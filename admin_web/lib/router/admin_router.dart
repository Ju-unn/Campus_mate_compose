import 'package:campus_mate_admin/billing/billing_screen.dart';
import 'package:campus_mate_admin/gate/gate_controller.dart';
import 'package:campus_mate_admin/gate/gate_stage.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_review_screen.dart';
import 'package:campus_mate_admin/reports/report_detail_screen.dart';
import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:campus_mate_admin/reports/report_list_screen.dart';
import 'package:campus_mate_admin/screens/login_screen.dart';
import 'package:campus_mate_admin/screens/mfa_enroll_screen.dart';
import 'package:campus_mate_admin/screens/mfa_verify_screen.dart';
import 'package:campus_mate_admin/screens/placeholder_screen.dart';
import 'package:campus_mate_admin/screens/status_screens.dart';
import 'package:campus_mate_admin/shell/admin_section.dart';
import 'package:campus_mate_admin/shell/admin_shell.dart';
import 'package:campus_mate_admin/users/user_detail_screen.dart';
import 'package:campus_mate_admin/users/user_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 관문 화면 주소. 셸 메뉴 주소는 [AdminSection].
abstract final class GatePaths {
  static const String loading = '/loading';
  static const String setup = '/setup';
  static const String login = '/login';
  static const String enroll = '/mfa/enroll';
  static const String verify = '/mfa/verify';
  static const String mfaRequired = '/mfa/required';
  static const String forbidden = '/forbidden';
  static const String unavailable = '/unavailable';

  /// 로그인 화면에 "구글 로그인을 마치지 못했어요" 를 띄우라는 표시(`failed=1`). 화면은 값까지 정확히 비교한다.
  static const String loginFailedParam = 'failed';
  static const String loginFailedQuery = '$loginFailedParam=1';
}

/// 관문 단계에 맞는 주소로 보낸다. 판정 전(null)은 불러오는 중, 준비가 끝나면 메뉴 화면만 연다.
///
/// 관문 쪽으로 돌릴 때 처음 연 메뉴 주소(쿼리 포함)를 기억했다가 준비가 끝나면 그리로 되돌린다 —
/// 디스코드 알림 링크(`/reports/{id}` 등)를 눌러 들어와 2단계를 거쳐도 그 화면이 열리게. 관문 화면 · 모르는 주소는
/// 기억하지 않는다(홈으로). 구글 로그인은 페이지를 떠났다 오므로 그 사이의 기억은 남지 않는다.
class GateRedirector {
  String? _wanted;

  /// 구글에서 실패 · 취소로 돌아온 것(?error=)을 봤다 — 판정 중(/loading)을 거치며 주소에서 사라지므로 기억해 둔다.
  bool _authFailed = false;

  /// supabase_flutter 가 웹에서 지우는 구글 로그인 복귀 매개변수(clear_auth_url_parameters.dart)와 같은 목록.
  /// 성공하면 supabase 가 이미 지우고 앱이 뜨지만, 실패(?error=)하면 남아서 여기서 한 번 더 지운다.
  /// `type` 은 뺐다 — 다음 조각의 목록 필터(신고 대상 종류 등)가 같은 이름을 쓸 수 있다.
  static const Set<String> _authParameters = {
    'code',
    'access_token',
    'expires_in',
    'expires_at',
    'refresh_token',
    'token_type',
    'provider_token',
    'provider_refresh_token',
    'error',
    'error_code',
    'error_description',
  };

  static bool _isAuthFailure(Uri uri) {
    final query = uri.queryParameters;
    return query.containsKey('error') || query.containsKey('error_code') || query.containsKey('error_description');
  }

  static Uri _withoutAuth(Uri uri) {
    if (!uri.queryParameters.keys.any(_authParameters.contains)) return uri;
    final query = Map.of(uri.queryParametersAll)..removeWhere((key, _) => _authParameters.contains(key));
    return Uri(path: uri.path, queryParameters: query.isEmpty ? null : query);
  }

  String? redirect(GateStage? stage, Uri uri) {
    final path = uri.path;
    final clean = _withoutAuth(uri).toString();
    if (stage == null || stage is SignedOut) {
      if (_isAuthFailure(uri)) _authFailed = true;
    } else {
      // 로그인 밖 단계(2단계 · 권한 없음 · 셸 …)로 판정됐다 — 실패 표시는 그 로그인 시도 몫이라 버린다.
      // 남겨 두면 나중에 로그아웃했을 때 로그인 화면에 실패 줄이 잘못 뜬다.
      _authFailed = false;
    }
    final target = switch (stage) {
      null => GatePaths.loading,
      ConfigMissing() => GatePaths.setup,
      SignedOut() => GatePaths.login,
      EnrollMfa() => GatePaths.enroll,
      VerifyMfa() => GatePaths.verify,
      MfaRequired() => GatePaths.mfaRequired,
      NotAdmin() => GatePaths.forbidden,
      Unavailable() => GatePaths.unavailable,
      Ready() => null,
    };
    if (target != null) {
      if (AdminSection.ownerOf(path) != null) _wanted = clean;
      if (path == target) return null;
      // 구글에서 실패 · 취소로 돌아왔으면(?error=) 로그인 화면이 오류 줄을 띄우게 표시를 달아 보낸다(pen A0_로그인_실패).
      if (stage is SignedOut && _authFailed) {
        _authFailed = false;
        return '$target?${GatePaths.loginFailedQuery}';
      }
      return target;
    }
    final wanted = _wanted;
    _wanted = null;
    if (wanted != null && wanted != uri.toString()) return wanted;
    if (AdminSection.ownerOf(path) == null) return AdminSection.home.path;
    return clean == uri.toString() ? null : clean;
  }
}

final adminRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  final redirector = GateRedirector();
  ref.listen(gateProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    initialLocation: AdminSection.home.path,
    refreshListenable: refresh,
    // 다시 판정하는 동안에도 앞 단계(value)를 그대로 써서 화면이 불러오는 중으로 깜빡이지 않게 한다.
    redirect: (context, state) => redirector.redirect(ref.read(gateProvider).value, state.uri),
    // 메뉴 아래 주소인데 아직 화면이 없으면(다음 조각에서 상세 화면을 더하기 전) 홈으로.
    onException: (context, state, router) => router.go(AdminSection.home.path),
    routes: [
      _page(GatePaths.loading, const LoadingScreen()),
      _page(GatePaths.setup, const ConfigMissingScreen()),
      _page(GatePaths.login, const LoginScreen()),
      _page(GatePaths.enroll, const MfaEnrollScreen()),
      _page(GatePaths.verify, const MfaVerifyScreen()),
      _page(GatePaths.mfaRequired, const MfaRequiredScreen()),
      _page(GatePaths.forbidden, const ForbiddenScreen()),
      _page(GatePaths.unavailable, const UnavailableScreen()),
      ShellRoute(
        builder: (context, state, child) {
          final section = AdminSection.ownerOf(state.uri.path) ?? AdminSection.home;
          return AdminShell(section: section, title: section.titleOf(state.uri.path), child: child);
        },
        routes: [for (final section in AdminSection.values) ..._sectionRoutes(section)],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// 메뉴 화면과 그 아래 상세 자리(`/heart-tasks/{id}` — 디스코드 알림 링크). 홈은 아래 자리가 없다.
/// 상세 주소는 목록 안에 겹치지(nested) 않고 나란히 둔다 — 겹치면 밑에 깔린 목록 페이지가 그려지지 않은 채
/// SelectionArea 가 그 글자를 재려다 멈춘다(10-18 시험에서 확인). 상세 주소도 같은 화면을 열고 그 건을 고른다.
List<GoRoute> _sectionRoutes(AdminSection section) {
  GoRoute route(String path) => GoRoute(
    path: path,
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      // 글자 끌어 복사는 페이지마다(셸 전체가 아니라 — admin_shell.dart 주석)
      child: SelectionArea(child: _sectionScreen(section, state.pathParameters['id'], state.extra)),
    ),
  );
  return [route(section.path), if (section != AdminSection.home) route('${section.path}/:id')];
}

/// 메뉴마다 화면. 아직 만들지 않은 메뉴는 자리 표시.
/// 신고는 목록과 상세가 다른 화면이다(pen A4 — 상세는 목록 옆이 아니라 따로). [extra] 는 목록에서 고른 줄(머리줄을 먼저 그린다).
Widget _sectionScreen(AdminSection section, String? id, Object? extra) {
  return switch (section) {
    AdminSection.heartTasks => HeartTaskReviewScreen(initialId: id),
    AdminSection.reports when id == null => const ReportListScreen(),
    AdminSection.reports => ReportDetailScreen(id: id!, summary: extra is ReportSummary && extra.id == id ? extra : null),
    // 사용자는 목록(찾기)과 상세가 다른 화면이다(pen A5). 주소에는 사람 번호뿐 — 학교 메일 · 검색어는 주소 · extra 에 싣지 않는다.
    AdminSection.users when id == null => const UserListScreen(),
    AdminSection.users => UserDetailScreen(id: id!),
    // 결제 아래 주소는 따로 없다(주문 번호를 주소에 싣지 않는다) — 어떤 주소로 와도 이 한 화면
    AdminSection.billing => const BillingScreen(),
    _ => PlaceholderScreen(section: section),
  };
}

/// 메뉴는 하루에도 수십 번 오간다 — 화면 전환 움직임 없이 바로 바꾼다.
GoRoute _page(String path, Widget child) {
  return GoRoute(path: path, pageBuilder: (context, state) => NoTransitionPage<void>(child: child));
}
