import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 18a 에 들어올 때마다 새로 읽는다(autoDispose). 제출이 성공하면 [HeartTaskSubmitViewModel] 이 이 provider 를
/// 버려 다시 읽게 한다 — 18c 에서 뒤로 오면 "검수중" 이 보인다.
final heartTasksViewModelProvider =
    NotifierProvider.autoDispose<HeartTasksViewModel, HeartTasksUiState>(HeartTasksViewModel.new);

class HeartTasksViewModel extends Notifier<HeartTasksUiState> {
  @override
  HeartTasksUiState build() {
    Future.microtask(_load);
    return const HeartTasksUiState();
  }

  Future<void> _load() async {
    final result = await ref.read(heartTaskRepositoryProvider).fetchTasks();
    // 응답을 기다리는 동안 18a 를 떠나면 autoDispose 로 이미 버려졌다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (tasks) => HeartTasksUiState(isLoading: false, tasks: tasks),
      onFailure: (failure) => HeartTasksUiState(isLoading: false, errorMessage: failure.toDisplayMessage()),
    );
  }
}
