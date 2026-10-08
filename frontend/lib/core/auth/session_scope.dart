import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

/// 로그아웃하면 앱이 들고 있던 기억(provider 상태)을 통째로 버린다.
///
/// provider 는 채팅방 하나 빼고 autoDispose 가 아니라 화면을 떠나도 값이 남는다 — 같은 폰에서
/// 다른 계정으로 들어오면 앞 사람의 내 프로필 · 카드 · 대화 목록이 그대로 보인다.
/// 비울 provider 목록을 두면 새 provider 가 생길 때마다 빠뜨리기 쉬워 [ProviderScope] 를 새로 만든다.
/// 로그아웃 버튼(16g)뿐 아니라 세션 만료로 튕길 때도 같이 비워진다.
///
/// [overrides] 는 새로 만드는 [ProviderScope] 마다 그대로 넣는다 — 앱을 켤 때 한 번 준비해 로그아웃해도 잃으면 안 되는
/// 것(디스크를 읽어 둔 온보딩 임시 저장소)만 둔다. 그 안의 값은 버리지 않으므로 지울 일은 그쪽이 맡는다(`sign_out.dart`).
class SessionScope extends StatefulWidget {
  const SessionScope({required this.authChanges, required this.child, this.overrides = const [], super.key});

  final Stream<AuthState> authChanges;
  final Widget child;
  final List<Override> overrides;

  @override
  State<SessionScope> createState() => _SessionScopeState();
}

class _SessionScopeState extends State<SessionScope> {
  late final StreamSubscription<AuthState> _subscription;

  /// 로그아웃할 때마다 하나 오른다. [ProviderScope] 의 key 라 바뀌면 아래가 전부 새로 만들어진다.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.authChanges.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) {
          setState(() => _generation++);
        }
      },
      // 세션 복구 실패 같은 오류도 이 스트림으로 온다 — 이동 판단은 AuthSessionListenable 이 한다.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(key: ValueKey(_generation), overrides: widget.overrides, child: widget.child);
  }
}
