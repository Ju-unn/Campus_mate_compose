import 'package:campus_mate/tour/model/tour_seen_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 투어 진행 상태. 단계 목록(`tour/view/app_tour_steps.dart`)의 몇째 단계를 보이는지만 든다 —
/// 화면 이동 · 대상 찾기 · 그리기는 호스트(`AppTourHost`)가 한다.
class AppTourUiState {
  const AppTourUiState({this.active = false, this.index = 0, this.skipped = 0, this.run = 0});

  final bool active;

  /// 단계 목록의 몇째 단계인가(0 부터).
  final int index;

  /// 대상을 못 찾아 건너뛴 단계 수. 단계 표시 "n / 총" 은 이만큼 줄여 센다.
  final int skipped;

  /// 투어를 시작할 때마다 오른다 — 같은 첫 단계로 다시 시작해도 호스트가 새로 찾게 한다.
  final int run;

  AppTourUiState copyWith({bool? active, int? index, int? skipped}) => AppTourUiState(
        active: active ?? this.active,
        index: index ?? this.index,
        skipped: skipped ?? this.skipped,
        run: run,
      );
}

/// 지금 로그인한 계정(프로필 id). 기본은 모름(null) — 앱은 main.dart 가 Supabase 세션으로 덮어쓴다.
/// 모르면 자동 시작하지 않는다(화면 시험이 Supabase 없이 홈을 띄워도 투어가 끼어들지 않는다).
final tourAccountIdProvider = Provider<String? Function()>((ref) => () => null);

final appTourViewModelProvider = NotifierProvider<AppTourViewModel, AppTourUiState>(AppTourViewModel.new);

/// 가입 후 학교가 열린 홈에 처음 왔을 때 한 번(계정별) 앱 투어를 띄우고, 설정 "가이드 다시 보기" 로 다시 띄운다.
class AppTourViewModel extends Notifier<AppTourUiState> {
  /// 처음 1회 자동 시작을 켤지. E2E 진입점(`integration_test/e2e_test.dart`)이 `app.main()` 전에 끈다 —
  /// 하네스는 가설마다 새 계정을 만들어 덮개가 기존 가설을 막는다. 다시 보기([replay])는 꺼도 된다.
  static bool autoStartEnabled = true;

  /// 저장소를 읽는 동안 또 불리면(홈이 다시 그려짐) 한 번만 본다.
  bool _checking = false;

  @override
  AppTourUiState build() => const AppTourUiState();

  /// 이 계정이 본 적이 없으면 시작한다. **시작하는 순간 본 것으로 저장한다** — 중간에 앱을 꺼도 끝난 것으로 친다.
  /// 학교 오픈 여부는 부르는 쪽(홈)이 본다. 저장소를 못 읽으면 띄우지 않는다.
  Future<void> autoStart() async {
    final profileId = ref.read(tourAccountIdProvider)();
    if (!autoStartEnabled || state.active || _checking || profileId == null) return;
    _checking = true;
    try {
      final store = ref.read(tourSeenStoreProvider);
      if (await store.hasSeen(profileId)) return;
      await store.markSeen(profileId);
    } on Object catch (error) {
      debugPrint('앱 투어 기록을 못 읽어 띄우지 않는다 (${error.runtimeType})');
      return;
    } finally {
      _checking = false;
    }
    if (ref.mounted) replay();
  }

  /// 첫 단계부터 다시 시작한다(본 적이 있어도).
  void replay() => state = AppTourUiState(active: true, run: state.run + 1);

  void next() => state = state.copyWith(index: state.index + 1);

  /// 이 단계의 대상을 끝내 못 찾았다 — 건너뛰고 단계 수에서 뺀다.
  void skipMissing() => state = state.copyWith(index: state.index + 1, skipped: state.skipped + 1);

  void end() => state = state.copyWith(active: false);
}
