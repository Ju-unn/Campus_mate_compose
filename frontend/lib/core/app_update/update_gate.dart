import 'package:campus_mate/core/app_update/update_required_screen.dart';
import 'package:campus_mate/core/app_update/update_requirement.dart';
import 'package:campus_mate/core/app_update/update_requirement_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 맨 위(`MaterialApp.builder`, 라우터 바깥)에서 [child](라우터)를 감싸, 서버가 정한 최소 버전보다 낮은 앱이면
/// 라우터 대신 [UpdateRequiredScreen] 을 그린다 — 딥링크 · 푸시로 어디를 열어도 막힌다.
///
/// 막는 것은 **업데이트가 필요하다고 확인된 때뿐**이다: 조회 중 · 조회 실패 · 필요 없음은 [child] 그대로다
/// (서버 장애가 앱 잠금이 되지 않게). 다시 확인하는 중에는 앞의 답을 들고 있어 화면이 깜빡이지 않는다.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requirement = ref.watch(updateRequirementProvider).value;
    return switch (requirement) {
      UpdateRequired(:final storeUrl) => UpdateRequiredScreen(storeUrl: storeUrl),
      _ => child,
    };
  }
}
