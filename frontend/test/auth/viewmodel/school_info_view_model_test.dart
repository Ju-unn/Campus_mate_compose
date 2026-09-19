import 'package:campus_mate/auth/model/department.dart';
import 'package:campus_mate/auth/model/school_info_repository_provider.dart';
import 'package:campus_mate/auth/model/student_number.dart';
import 'package:campus_mate/auth/viewmodel/school_info_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/school_info_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_school_info_repository.dart';

void main() {
  late FakeSchoolInfoRepository repository;

  setUp(() {
    repository = FakeSchoolInfoRepository();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [schoolInfoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  SchoolInfoUiState readState(ProviderContainer container) {
    return container.read(schoolInfoViewModelProvider);
  }

  /// 학과·학번을 모두 채워, 제출할 수 있는 ViewModel 을 만든다.
  SchoolInfoViewModel buildSubmittableViewModel(ProviderContainer container) {
    final viewModel = container.read(schoolInfoViewModelProvider.notifier);
    viewModel.changeDepartment('컴퓨터공학과');
    viewModel.changeStudentNumber('20240001');
    return viewModel;
  }

  test('학과가 형식에 맞으면 department 가 채워진다', () {
    final container = buildContainer();
    final viewModel = container.read(schoolInfoViewModelProvider.notifier);

    viewModel.changeDepartment('컴퓨터공학과');

    expect(readState(container).department, Department.tryParse('컴퓨터공학과'));
    expect(readState(container).departmentInput, '컴퓨터공학과');
  });

  test('학과가 형식에 어긋나면 department 가 비어 제출할 수 없다', () {
    final container = buildContainer();
    final viewModel = container.read(schoolInfoViewModelProvider.notifier);

    viewModel.changeDepartment('   ');

    expect(readState(container).department, isNull);
    expect(readState(container).canSubmit, isFalse);
  });

  test('학번이 형식에 맞으면 studentNumber 가 채워진다', () {
    final container = buildContainer();
    final viewModel = container.read(schoolInfoViewModelProvider.notifier);

    viewModel.changeStudentNumber('20240001');

    expect(readState(container).studentNumber, StudentNumber.tryParse('20240001'));
    expect(readState(container).studentNumberInput, '20240001');
  });

  test('학과·학번이 아직 없으면 submit() 이 아무 일도 하지 않는다', () async {
    final container = buildContainer();
    final viewModel = container.read(schoolInfoViewModelProvider.notifier);

    await viewModel.submit();

    expect(repository.submittedDepartments, isEmpty);
    expect(readState(container).completed, isFalse);
  });

  test('제출에 성공하면 completed 가 true 가 된다', () async {
    repository.nextSubmitResult = const Success(null);
    final container = buildContainer();
    final viewModel = buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(repository.submittedDepartments, [Department.tryParse('컴퓨터공학과')]);
    expect(repository.submittedStudentNumbers, [StudentNumber.tryParse('20240001')]);
    expect(readState(container).completed, isTrue);
    expect(readState(container).isSubmitting, isFalse);
  });

  test('제출에 실패하면 errorMessage 가 채워지고 completed 는 그대로다', () async {
    repository.nextSubmitResult = const FailureResult(ServerRejectedFailure('이미 제출한 정보예요'));
    final container = buildContainer();
    final viewModel = buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(readState(container).errorMessage, '이미 제출한 정보예요');
    expect(readState(container).completed, isFalse);
    expect(readState(container).isSubmitting, isFalse);
  });

  test('제출 중에는 canSubmit 이 false 다', () async {
    final container = buildContainer();
    final viewModel = buildSubmittableViewModel(container);

    final future = viewModel.submit();

    expect(readState(container).isSubmitting, isTrue);
    expect(readState(container).canSubmit, isFalse);
    await future;
  });

  test('저장소가 Result 밖으로 예외를 던져도 isSubmitting 이 갇히지 않는다', () async {
    repository.nextSubmitError = ArgumentError('세션이 만료됐다');
    final container = buildContainer();
    final viewModel = buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(readState(container).isSubmitting, isFalse);
    expect(readState(container).completed, isFalse);
    expect(readState(container).errorMessage, isNotNull);
  });
}
