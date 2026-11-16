import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sentRequestsViewModelProvider =
    NotifierProvider<SentRequestsViewModel, SentRequestsUiState>(SentRequestsViewModel.new);

/// 보낸 신청(대화 탭의 [보낸 신청] 탭, 2026-10-13 사용자 결정 B · 2026-11-16 탭 나누기). 상태 판정 · 남기는 기간은 서버가 하고
/// 앱은 목록을 그대로 그린다. 읽는 방식은 받은 신청([AcceptancesViewModel])과 같다 — 조용한 읽기, 읽는 중 합치기.
/// 하단 내비 숫자(§8.8)에는 넣지 않는다 — 나를 기다리는 사람이 아니라 내가 기다리는 사람이다.
///
/// **그 탭을 처음 열 때([open])만 읽는다**(사용자 「보낸신청 api로딩해야하고 , 대화도 로딩해야하는데 낭비」). 그 전에는 새로고침
/// 경로(앱 복귀 · 푸시 · 사용자 채널 · 대화 탭 진입)가 [refresh] 를 불러도 서버를 부르지 않는다. 한 번 연 뒤에는 그대로 다시 읽는다.
class SentRequestsViewModel extends Notifier<SentRequestsUiState> {
  Future<void>? _inFlight;

  /// [보낸 신청] 탭을 연 적이 있다(또는 방금 신청을 보냈다). 상태가 아니라 읽을지 말지만 가르는 표시다.
  bool _opened = false;

  /// 진행 중인 읽기에 조용하지 않은 호출이 합쳐졌다 — 끝난 뒤 조용하지 않게 한 번 더 읽는다(받은 신청과 같다).
  bool _readAgain = false;

  /// 10b 에서 방금 대화 신청을 보냈다. 상태가 아니라 한 번 꺼내 가는 표시다 — 대화 탭이 토스트 · 스크롤에 한 번 쓴다.
  bool _justSent = false;

  /// announceSent 마다 올라가는 세대. 이전 세대에서 시작한 읽기는 결과가 와도 그리지 않는다.
  int _generation = 0;

  @override
  SentRequestsUiState build() {
    // 만들어지기만 해서는 읽지 않는다 — [open] 이 처음 읽는다.
    return const SentRequestsUiState();
  }

  /// [보낸 신청] 탭이 보일 때마다 부른다 — 처음이면 읽기 시작(로딩부터), 그 뒤로는 조용히 다시 읽는다.
  /// 첫 읽기는 isLoading 이라 quiet 여도 실패를 보인다(받은 신청과 같다).
  Future<void> open() {
    _opened = true;
    return refresh(quiet: true);
  }

  /// [quiet] 은 앱 복귀 · 화면 진입 때 자동으로 읽는 경우다 — 실패해도 이미 보이는 줄을 그대로 두고 오류 줄을 새로 띄우지 않는다.
  /// 탭을 한 번도 열지 않았으면 아무것도 하지 않는다.
  Future<void> refresh({bool quiet = false}) {
    if (!_opened) return Future.value();
    final running = _inFlight;
    if (running == null) {
      return _inFlight = _loadAndRepeat(quiet).whenComplete(() => _inFlight = null);
    }
    _readAgain = _readAgain || !quiet;
    return running;
  }

  Future<void> _loadAndRepeat(bool quiet) async {
    await _load(quiet: quiet);
    while (_readAgain) {
      _readAgain = false;
      await _load(quiet: false);
    }
  }

  Future<void> _load({required bool quiet}) async {
    final generation = _generation;
    final result = await ref.read(cardRepositoryProvider).fetchSentRequests();
    if (generation != _generation) return;
    state = result.when(
      onSuccess: (list) => state.copyWith(isLoading: false, requests: list),
      onFailure: (failure) => quiet && !state.isLoading
          ? state
          : state.copyWith(isLoading: false, error: failure),
    );
  }

  /// 10b 에서 대화 신청을 보낸 직후(대화 탭으로 옮기기 전) 부른다. 새 줄이 빠진 옛 목록이 먼저 그려졌다가
  /// 줄이 끼어들지 않게 처음처럼 로딩부터 다시 읽는다.
  Future<void> announceSent() {
    _justSent = true;
    _opened = true; // 대화 탭이 [보낸 신청] 탭을 열어 보여 준다
    _generation += 1;
    state = const SentRequestsUiState();
    return refresh();
  }

  /// 방금 신청을 보내고 넘어왔는지 꺼내고 지운다 — 대화 탭이 들어올 때 한 번.
  bool takeJustSent() {
    final justSent = _justSent;
    _justSent = false;
    return justSent;
  }
}
