import 'package:campus_mate/billing/task/model/data/heart_task.dart';
import 'package:campus_mate/common/failure.dart';

/// 18a 무료로 하트 모으기의 상태. 읽기가 끝나면 늘 새로 만든다(바꿀 칸이 없다).
class HeartTasksUiState {
  const HeartTasksUiState({this.isLoading = true, this.tasks = const [], this.error});

  final bool isLoading;
  final List<HeartTask> tasks;

  /// 읽기 실패의 종류. 글자는 view 가 `context.errorText` 로 만든다.
  final Failure? error;
}
