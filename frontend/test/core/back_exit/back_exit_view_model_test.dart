import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late BackExitViewModel viewModel;

  setUp(() {
    now = DateTime(2026, 10, 13, 12);
    viewModel = BackExitViewModel(now: () => now);
  });

  test('안내 문구는 "한 번 더 누르면 종료돼요" 다', () {
    expect(backExitMessage, '한 번 더 누르면 종료돼요');
  });

  test('처음 뒤로가기는 안내만 하고 종료하지 않는다', () {
    expect(viewModel.onBackPressed(), BackExitAction.showHint);
  });

  test('2초 안에 한 번 더 누르면 종료한다', () {
    viewModel.onBackPressed();
    now = now.add(const Duration(milliseconds: 1900));

    expect(viewModel.onBackPressed(), BackExitAction.exit);
  });

  test('딱 2초가 지났으면 다시 안내한다', () {
    viewModel.onBackPressed();
    now = now.add(const Duration(seconds: 2));

    expect(viewModel.onBackPressed(), BackExitAction.showHint);
  });

  test('2초가 지난 뒤에는 다시 안내하고, 그 뒤 2초 안에 누르면 종료한다', () {
    viewModel.onBackPressed();
    now = now.add(const Duration(seconds: 5));
    expect(viewModel.onBackPressed(), BackExitAction.showHint);

    now = now.add(const Duration(seconds: 1));
    expect(viewModel.onBackPressed(), BackExitAction.exit);
  });

  test('종료를 돌려준 다음 뒤로가기는 처음부터 다시 센다', () {
    viewModel.onBackPressed();
    viewModel.onBackPressed();

    expect(viewModel.onBackPressed(), BackExitAction.showHint);
  });
}
