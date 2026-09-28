import 'package:campus_mate/billing/model/heart_task.dart';

/// 18a 무료로 하트 모으기의 상태. 읽기가 끝나면 늘 새로 만든다(바꿀 칸이 없다).
class HeartTasksUiState {
  const HeartTasksUiState({this.isLoading = true, this.tasks = const [], this.errorMessage});

  final bool isLoading;
  final List<HeartTask> tasks;
  final String? errorMessage;
}
