import 'package:campus_mate/auth/gate/model/data/verification_gate.dart';
import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/school_info/model/data/academic_status.dart';
import 'package:campus_mate/auth/school_info/model/data/department.dart';
import 'package:campus_mate/auth/school_info/model/data/student_number.dart';
import 'package:campus_mate/auth/school_info/model/repository/school_info_repository_provider.dart';
import 'package:campus_mate/auth/school_info/viewmodel/school_info_ui_state.dart';
import 'package:campus_mate/auth/school_info/viewmodel/school_info_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/graduate/model/data/verification_method.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../gate/model/repository/fake_verification_gate_repository.dart';
import '../model/repository/fake_school_info_repository.dart';

void main() {
  late FakeSchoolInfoRepository repository;
  late FakeVerificationGateRepository gateRepository;

  setUp(() {
    repository = FakeSchoolInfoRepository();
    gateRepository = FakeVerificationGateRepository();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        schoolInfoRepositoryProvider.overrideWithValue(repository),
        verificationGateRepositoryProvider.overrideWithValue(gateRepository),
      ],
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
    viewModel.changeStudentNumber('21');
    viewModel.changeAcademicStatus(AcademicStatus.undergraduate);
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

    viewModel.changeStudentNumber('21');

    expect(readState(container).studentNumber, StudentNumber.tryParse('21'));
    expect(readState(container).studentNumberInput, '21');
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
    expect(repository.submittedStudentNumbers, [StudentNumber.tryParse('21')]);
    expect(readState(container).completed, isTrue);
    expect(readState(container).isSubmitting, isFalse);
  });

  test('제출에 성공하면 라우터가 3c 를 벗어나도록 게이트를 다시 조회한다', () async {
    final container = buildContainer();
    final viewModel = buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(gateRepository.fetchCount, 1);
  });

  test('제출에 실패하면 게이트를 다시 조회하지 않는다', () async {
    repository.nextSubmitResult = const FailureResult(ServerRejectedFailure('이미 제출한 정보예요'));
    final container = buildContainer();
    final viewModel = buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(gateRepository.fetchCount, 0);
  });

  test('제출에 실패하면 error 가 채워지고 completed 는 그대로다', () async {
    repository.nextSubmitResult = const FailureResult(ServerRejectedFailure('이미 제출한 정보예요'));
    final container = buildContainer();
    final viewModel = buildSubmittableViewModel(container);

    await viewModel.submit();

    expect((readState(container).error! as ServerRejectedFailure).serverMessage, '이미 제출한 정보예요');
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
    expect(readState(container).error, isA<UnknownFailure>());
  });

  // 11-17: 보내는 사이 로그아웃으로 버려지면 늦게 온 답이 버려진 상태 · ref 를 건드려 던진다(catch 안에서 또 던진다).
  test('보내는 사이 버려지면 늦게 온 답은 버린다 — 던지지 않는다', () async {
    final container = buildContainer();
    final pending = buildSubmittableViewModel(container).submit();

    container.dispose();

    await expectLater(pending, completes);
  });

  // 대장 판정(11-24): 시안에 문구가 없어 서버와 같은 글("입력한 값을 다시 확인해 주세요")을 칸 아래에 띄운다.
  // 한글 입력기는 조합 중에 자모("경ㅇ")를 먼저 넣어서, 쓰는 도중에는 띄우지 않고 손을 멈춘 뒤(닉네임과 같은 300ms) 띄운다.
  group('학과 칸 아래 오류', () {
    testWidgets('서버가 거절할 학과는 손을 멈춘 뒤에 오류를 띄우고, 그 전에도 제출할 수 없다', (tester) async {
      final container = buildContainer();
      container.read(schoolInfoViewModelProvider.notifier).changeDepartment('...');
      expect(readState(container).departmentError, isNull, reason: '쓰는 도중에는 띄우지 않는다');
      expect(readState(container).canSubmit, isFalse);

      await tester.pump(const Duration(milliseconds: 350));

      expect(readState(container).departmentError, const AppErrorFailure(AppError.invalidInput));
    });

    testWidgets('아직 쓰지 않은 빈 칸에는 오류를 띄우지 않는다', (tester) async {
      final container = buildContainer();
      container.read(schoolInfoViewModelProvider.notifier).changeDepartment('');

      await tester.pump(const Duration(milliseconds: 350));

      expect(readState(container).departmentError, isNull);
    });

    testWidgets('고쳐 쓰면 오류가 바로 지워진다', (tester) async {
      final container = buildContainer();
      final viewModel = container.read(schoolInfoViewModelProvider.notifier);
      viewModel.changeDepartment('...');
      await tester.pump(const Duration(milliseconds: 350));

      viewModel.changeDepartment('컴공');
      expect(readState(container).departmentError, isNull);
      await tester.pump(const Duration(milliseconds: 350));

      expect(readState(container).departmentError, isNull);
    });

    testWidgets('기다리는 사이 버려져도 던지지 않는다', (tester) async {
      final container = ProviderContainer(
        overrides: [
          schoolInfoRepositoryProvider.overrideWithValue(repository),
          verificationGateRepositoryProvider.overrideWithValue(gateRepository),
        ],
      );
      container.read(schoolInfoViewModelProvider.notifier).changeDepartment('...');
      container.dispose();

      await tester.pump(const Duration(milliseconds: 350));
    });
  });

  // 신분(1.0.7 1-1) — 필수. 졸업증명서로 인증한 사람만 "졸업생" 을 미리 골라 둔다(관문 조회가 실어 온 방법, 따로 묻지 않음).
  group('신분', () {
    Future<ProviderContainer> containerAfterGate(VerificationMethod? method) async {
      gateRepository
        ..nextResult = const Success(VerificationGate.needsSchoolInfo)
        ..nextMethod = method;
      final container = buildContainer();
      await container.read(verificationGateListenableProvider).refresh();
      return container;
    }

    test('졸업증명서로 인증했으면 졸업생이 골라진 채 열린다', () async {
      final container = await containerAfterGate(VerificationMethod.graduateCertificate);

      expect(readState(container).academicStatus, AcademicStatus.alumni);
    });

    test('학교 메일 · 방법 없음이면 아무것도 안 고른 채 열리고, 학과 · 학번을 채워도 [다음] 이 꺼져 있다', () async {
      for (final method in [VerificationMethod.schoolEmail, null]) {
        final container = await containerAfterGate(method);
        final viewModel = container.read(schoolInfoViewModelProvider.notifier)
          ..changeDepartment('컴퓨터공학과')
          ..changeStudentNumber('21');

        expect(readState(container).academicStatus, isNull, reason: '$method');
        expect(readState(container).canSubmit, isFalse, reason: '$method');
        await viewModel.submit();
        expect(repository.submittedStatuses, isEmpty, reason: '$method');
      }
    });

    test('미리 골라진 졸업생을 다른 칩으로 바꾸면 바꾼 값을 보낸다 — 저장은 [다음] 때만', () async {
      final container = await containerAfterGate(VerificationMethod.graduateCertificate);
      final viewModel = container.read(schoolInfoViewModelProvider.notifier)
        ..changeDepartment('컴퓨터공학과')
        ..changeStudentNumber('21')
        ..changeAcademicStatus(AcademicStatus.graduateStudent);
      expect(repository.submittedStatuses, isEmpty, reason: '칩을 눌러도 아직 보내지 않는다');

      await viewModel.submit();

      expect(repository.submittedStatuses, [AcademicStatus.graduateStudent]);
    });
  });
}
