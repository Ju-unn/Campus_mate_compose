import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/bio_repository.dart';

class FakeBioRepository implements BioRepository {
  Result<String> nextDraftResult = const Success('안녕하세요! 활발한 성격이에요.');
  Result<void> nextSubmitResult = const Success(null);
  int draftCount = 0;
  String? submittedBio;

  @override
  Future<Result<String>> generateDraft() async {
    draftCount++;
    return nextDraftResult;
  }

  @override
  Future<Result<void>> submit(String bio) async {
    submittedBio = bio;
    return nextSubmitResult;
  }
}
