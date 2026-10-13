import 'package:campus_mate/core/haptics/haptics_gateway.dart';

/// 진동을 실제로 울리지 않고 몇 번 불렸는지만 센다.
class FakeHapticsGateway implements HapticsGateway {
  int selectionClicks = 0;

  @override
  Future<void> selectionClick() async => selectionClicks++;
}
