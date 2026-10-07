part of 'area5.dart';

// 영역 5 가짜 서버 응답 가설 4개(묶음 area5-fake — 폰 A: E-EDGE-05 · 06 · 07 · 08). PC 쪽은 e2e/area5_fake.py 의 같은 번호.
// lib/ 는 바꾸지 않는다 — 앱을 `apiClientProvider` 자리만 바꿔 끼워 다시 띄우고(E-HOME-26 과 같은 길), 진짜 http.Client 를 감싼 [_FkClient] 가
// 정한 `METHOD /경로` 만 서버에 보내지 않고 502 · 500 · 429 로 대신 답한다. 그 밖의 요청은 그대로 서버로 간다.
// 대신 답한 요청은 서버에 닿지 않으므로 DB 는 안 바뀌고 임베딩 · 이미지 생성(유료)도 안 나간다. PC 는 [_FkClient.faked] 로 그것을 확인한다.
// "정말 영구 삭제" 는 `_wdWithdraw` 로만 누른다 — 그리고 [_FkClient] 는 POST /account/withdraw 를 규칙이 없어도 서버에 보내지 않는다(안 보내는 쪽으로 닫힘).
// 이 파일의 이름은 모두 `_fk` 로 시작한다.
// 바꿔 끼움은 맨 위 ProviderScope 에 단다([_FkScope]) — 겹친 것은 저장소 provider 에 안 먹는다. 안 먹었으면 [_FkClient.built] 가 false 라 아무것도 누르기 전에 blocked.

/// 지켜보는 여섯 길 — 규칙이 없어 서버로 그냥 간 것을 [_FkClient.passed] 에 적는다.
const _fkWatched = ['PATCH /me/profile', 'PUT /me/photos', 'POST /account/withdraw', 'POST /me/avatar/regenerate', 'GET /me/profile', 'GET /me/card-preview'];

/// `METHOD /경로` 를 (METHOD, 경로) 로 가른다.
(String, String) _fkSplit(String rule) => (rule.split(' ').first, rule.split(' ').last);

class _FkClient extends http.BaseClient {
  _FkClient(this._inner);

  final http.Client _inner;

  /// `METHOD /경로` → 대신 줄 상태코드.
  final Map<String, int> rules = {};

  /// 대신 답한 요청(`METHOD /경로=상태`) · 서버로 그냥 간 요청(지켜보는 여섯 길만).
  final List<String> faked = [];
  final List<String> passed = [];

  /// 앱이 이 클라이언트로 요청을 보냈다(= 끼워 넣기가 먹혔다).
  bool built = false;

  bool _matches(String rule, http.BaseRequest request) {
    final (method, path) = _fkSplit(rule);
    return request.method == method && request.url.path.endsWith(path);
  }

  int? _statusFor(http.BaseRequest request) {
    for (final rule in rules.entries) {
      if (_matches(rule.key, request)) return rule.value;
    }
    return _matches('POST /account/withdraw', request) ? 502 : null; // 탈퇴는 규칙이 없어도 서버에 안 보낸다
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    built = true;
    final status = _statusFor(request);
    final key = '${request.method} ${request.url.path}';
    if (status == null) {
      if (_fkWatched.any((rule) => _matches(rule, request))) passed.add(key);
      return _inner.send(request);
    }
    faked.add('$key=$status');
    return Future.value(http.StreamedResponse(
      Stream.value(utf8.encode('{"detail":"e2e fake"}')),
      status,
      request: request,
      headers: const {'content-type': 'application/json'},
    ));
  }
}

/// SessionScope(lib/core/auth/session_scope.dart)와 같은 일을 하되 **맨 위 ProviderScope** 에 apiClientProvider 의 바꿔 끼움을 단다.
/// 겹친 ProviderScope 에 단 바꿔 끼움은 그 아래 위젯이 직접 읽는 provider 에만 먹는다(예: homeNowProvider) — 저장소 provider(meRepositoryProvider 등)는
/// 맨 위 컨테이너가 만들어 맨 위의 apiClientProvider 를 읽으므로 가짜가 한 번도 안 지났다(2026-10-07 기기 실행: 넷 다 blocked).
/// SessionScope 는 overrides 를 못 받아 lib 를 안 고치려고 같은 모양을 시험 쪽에 둔다 — 로그아웃(signedOut)마다 컨테이너를 새로 만드는 것까지 같다.
class _FkScope extends StatefulWidget {
  const _FkScope({required this.fake, super.key});

  final _FkClient fake;

  @override
  State<_FkScope> createState() => _FkScopeState();
}

class _FkScopeState extends State<_FkScope> {
  late final StreamSubscription<AuthState> _subscription;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) setState(() => _generation++);
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
        key: ValueKey(_generation),
        overrides: [
          apiClientProvider.overrideWith((ref) => ApiClient(
                Env.apiBaseUrl,
                widget.fake,
                Supabase.instance.client.auth,
                onFailure: ref.read(accountStatusListenableProvider).observe,
              )),
        ],
        child: const app.CampusMateApp(),
      );
}

/// 앱을 apiClientProvider 만 바꿔 끼워 다시 띄운다 — 로그인은 이어서 [_session] 이 한다.
_FkClient _fkInstall() {
  final fake = _FkClient(http.Client());
  runApp(_FkScope(key: UniqueKey(), fake: fake)); // 같은 타입이라 키가 없으면 옛 상태(옛 provider 컨테이너)를 그대로 이어 쓴다
  return fake;
}

typedef _FkBody = Future<Map<String, Object?>> Function(WidgetTester tester, Map<String, dynamic> job, _FkClient fake);

/// 가짜를 끼운 앱으로 로그인해 홈까지 간 뒤 [body] 를 돈다. 끼운 것이 안 먹었으면(홈이 가짜 클라이언트를 한 번도 안 지남) 아무것도 누르지 않고 blocked.
Area1Case _fkSession(_FkBody body) => (tester, job) async {
      final fake = _fkInstall();
      await tester.pump();
      return _session((tester, job) async {
        await arrive(tester, 'home');
        await wait(tester, const Duration(seconds: 2)); // 홈이 서버를 한 번은 부르게
        if (!fake.built) throw E2eBlocked('가짜 응답 끼우기가 안 먹음 — 로그인한 뒤 홈이 가짜 클라이언트를 한 번도 안 지남(아무것도 누르지 않음)');
        return {...await body(tester, job, fake), 'faked': fake.faked, 'passed': fake.passed};
      })(tester, job);
    };

/// 대신 줄 규칙 — job 의 status 를 [paths](`METHOD /경로`) 에 건다.
void _fkRules(_FkClient fake, Map<String, dynamic> job, List<String> paths) {
  fake.rules.addAll({for (final path in paths) path: job['status'] as int});
}

/// [expect] 문구가 떴는지 · 고친 값이 그대로인지 · 어느 화면에 남았는지.
Future<Map<String, Object?>> _fkRefused(WidgetTester tester, String place, Object? edited, String expect) async {
  final seen = await appears(tester, find.text(expect), const Duration(seconds: 15)) != null;
  return {'place': place, 'error': seen ? expect : null, 'kept': edited == null || _edValue(tester, place) == edited, 'stayed': _title(tester)};
}

/// 15-5 에서 15-6 · 15-7 을 열어 값을 고쳐 저장을 눌렀을 때.
Future<Map<String, Object?>> _fkSave(WidgetTester tester, String place, Map<String, dynamic> job) async {
  await _edEnter(tester, place);
  await _edEdit(tester, place, job);
  final edited = _edValue(tester, place);
  await _edTapSave(tester);
  final seen = await _fkRefused(tester, place, edited, job['expect'] as String);
  await _returnTo(tester, _actManageTitle);
  return seen;
}

/// 15 → 히어로 알약 → 15b "무료로 만들기" — 토스트 글자를 본다.
Future<Map<String, Object?>> _fkRegenerate(WidgetTester tester, Map<String, dynamic> job) async {
  await _returnTo(tester, '내 프로필');
  await _photoOpenSheet(tester);
  await _photoPress(tester, find.descendant(of: find.byType(SafetySheet), matching: find.text(_photoFreeCta)));
  return {...await _fkRefused(tester, 'avatar', null, job['expect'] as String), 'generating_gone': !_has(find.text(_photoGenerating))};
}

/// 설정 → 탈퇴하기 → 영구 삭제 → "정말 영구 삭제" — 가짜가 서버 대신 답하므로 계정은 그대로다. 최종 시트에 문구가 뜬다.
Future<Map<String, Object?>> _fkWithdraw(WidgetTester tester, Map<String, dynamic> job) async {
  // `_wdOpenFinal` 은 `_openMe` 로 시작해 홈 화면(HomeScreen)을 다시 찾는다 — 앞 걸음으로 이미 나 탭 안에 있어 홈이 안 지어진 채라 30초 뒤 실패했다(2026-10-07 기기 실행).
  // 그래서 나 탭(15)에 있는 채 설정부터 연다.
  await _returnTo(tester, '내 프로필');
  await pumpUntil(tester, find.byType(ProfileHero));
  await _openSettings(tester);
  await _openWithdrawSheet(tester);
  await _openFinalSheet(tester);
  await _wdWithdraw(tester);
  final expect = job['expect'] as String;
  final sheet = find.descendant(of: find.byType(WithdrawFinalSheet), matching: find.text(expect));
  final seen = await appears(tester, sheet, const Duration(seconds: 15)) != null;
  return {'place': 'withdraw', 'error': seen ? expect : null, 'sheet_open': _has(find.byType(WithdrawFinalSheet)), 'login': _has(screen('login'))};
}

const _fkLoadFail = '잠시 뒤 다시 시도해 주세요'; // me/view/me_load_error.dart
const _fkRetry = '다시 시도';

/// 읽기 실패 화면 하나 — 가짜가 읽기를 막은 채 [open] 으로 연 뒤 문구 · "다시 시도" 를 본다 → 가짜를 거두고 누르면 [loaded] 가 몇 ms 만에 뜨는지.
Future<Map<String, Object?>> _fkLoadError(
  WidgetTester tester,
  _FkClient fake,
  String place,
  String path,
  int status,
  Future<void> Function() open,
  Finder loaded,
) async {
  fake.rules['GET $path'] = status;
  await open();
  final error = await appears(tester, find.text(_fkLoadFail), const Duration(seconds: 15)) != null;
  final retry = find.text(_fkRetry);
  final hasRetry = _has(retry);
  fake.rules.remove('GET $path');
  final watch = Stopwatch()..start();
  if (hasRetry) await tap(tester, retry);
  int? recoveredMs;
  while (watch.elapsed < const Duration(seconds: 10)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_has(loaded)) {
      recoveredMs = watch.elapsedMilliseconds;
      break;
    }
  }
  return {'place': place, 'error': error ? _fkLoadFail : null, 'retry': hasRetry, 'recovered_ms': recoveredMs};
}

/// 05(502) · 06(500): 15-6 저장 · 15-7 저장 · 다시 만들기 · 영구 삭제 — PC 가 job['places'] 로 고른 곳을 이 차례로 돈다.
Future<Map<String, Object?>> _fkSaves(WidgetTester tester, Map<String, dynamic> job, _FkClient fake) async {
  final places = (job['places'] as List).cast<String>();
  _fkRules(fake, job, ['PATCH /me/profile', 'PUT /me/photos', 'POST /me/avatar/regenerate', 'POST /account/withdraw']);
  final walks = <Map<String, Object?>>[];
  await _openManage(tester);
  for (final place in ['15-6', '15-7']) {
    if (places.contains(place)) walks.add(await _fkSave(tester, place, job));
  }
  if (places.contains('avatar')) walks.add(await _fkRegenerate(tester, job));
  if (places.contains('withdraw')) walks.add(await _fkWithdraw(tester, job));
  return {'walks': walks};
}

final Map<String, Area1Case> area5CasesFake = {
  'E-EDGE-05': _fkSession(_fkSaves),
  'E-EDGE-06': _fkSession(_fkSaves),

  // 08(429): 15-6 저장 한 곳.
  'E-EDGE-08': _fkSession((tester, job, fake) async {
    _fkRules(fake, job, ['PATCH /me/profile']);
    await _openManage(tester);
    return {'walks': [await _fkSave(tester, '15-6', job)]};
  }),

  // 07: 15 · 15-5 · 15-4 를 읽기 실패 상태로 연다 — 15 는 처음 읽을 때, 15-5 는 열린 채 다시 읽을 때, 15-4 는 열 때. 상태코드는 job['status'].
  'E-EDGE-07': _fkSession((tester, job, fake) async {
    final status = job['status'] as int;
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final walks = <Map<String, Object?>>[];
    final hero = find.byType(ProfileHero);
    walks.add(await _fkLoadError(tester, fake, '15', '/me/profile', status, () async {
      container.invalidate(myProfileProvider);
      await tap(tester, _tab('나'));
    }, hero));
    await pumpUntil(tester, hero);
    walks.add(await _fkLoadError(tester, fake, '15-5', '/me/profile', status, () async {
      await tap(tester, _entry(_manageEntry));
      await pumpUntil(tester, find.text(_sectionTitles.first));
      fake.rules['GET /me/profile'] = status;
      container.invalidate(myProfileProvider);
    }, find.text(_sectionTitles.first)));
    await _returnTo(tester, '내 프로필');
    walks.add(await _fkLoadError(tester, fake, '15-4', '/me/card-preview', status, () async {
      await tap(tester, find.text(_previewEntry));
    }, find.byType(ProfileCard)));
    return {'walks': walks};
  }),
};
