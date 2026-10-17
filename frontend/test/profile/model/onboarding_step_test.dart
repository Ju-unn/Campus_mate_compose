import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 앞뒤는 서버 순서로 센다 — 앱 enum 은 avatar 자리가 다르다(photos 뒤).
  // 10-17 아바타 리빌 맨 끝 결정: 서버 순서에서 avatar 가 bio 뒤로 간다(서버는 아직 옛 순서 — 앱은 새 순서로 둔다).
  group('stepBack', () {
    const expected = <OnboardingStep, OnboardingStep?>{
      // 04-1 앞은 인증이 끝난 관문이라 돌아갈 곳이 없다(사용자 결정 ⑦).
      OnboardingStep.basicInfo: null,
      OnboardingStep.kakaoId: OnboardingStep.basicInfo,
      OnboardingStep.photos: OnboardingStep.kakaoId,
      // 사진 경계: 04-3 "다음" 에서 아바타가 이미 등록돼 04-4 → 04-2 뒤로는 출시 뒤다(사용자 결정 ①).
      OnboardingStep.appearanceType: null,
      OnboardingStep.interests: OnboardingStep.appearanceType,
      OnboardingStep.myTraits: OnboardingStep.interests,
      OnboardingStep.survey: OnboardingStep.myTraits,
      // 아바타 확인(05-12)은 가입 맨 끝(20 앞)으로 옮겨 뒤로가 없다. 06-1 의 앞은 설문이다.
      OnboardingStep.avatar: null,
      OnboardingStep.idealConditions: OnboardingStep.survey,
      OnboardingStep.idealTraits: OnboardingStep.idealConditions,
      OnboardingStep.idealNote: OnboardingStep.idealTraits,
      OnboardingStep.bio: OnboardingStep.idealNote,
      OnboardingStep.complete: null,
    };
    for (final MapEntry(key: step, value: back) in expected.entries) {
      test('${step.name} 의 앞 단계는 ${back?.name}', () {
        expect(step.stepBack(), back);
      });
    }

    test('모든 단계가 표에 있다', () {
      expect(expected.keys.toSet(), OnboardingStep.values.toSet());
    });
  });

  group('stepAfter', () {
    test('서버 순서대로 한 칸씩 간다', () {
      expect(OnboardingStep.basicInfo.stepAfter(), OnboardingStep.kakaoId);
      expect(OnboardingStep.photos.stepAfter(), OnboardingStep.appearanceType);
      // 설문을 다시 저장해도 05-12 를 다시 보이지 않고 06-1 로 간다(서버가 옛 순서여도 같다).
      expect(OnboardingStep.survey.stepAfter(), OnboardingStep.idealConditions);
      expect(OnboardingStep.bio.stepAfter(), OnboardingStep.avatar);
      expect(OnboardingStep.avatar.stepAfter(), OnboardingStep.complete);
    });

    test('끝 다음은 없다', () {
      expect(OnboardingStep.complete.stepAfter(), isNull);
    });
  });

  group('isBefore', () {
    test('서버 순서로 앞인지 본다', () {
      expect(OnboardingStep.survey.isBefore(OnboardingStep.idealConditions), isTrue);
      expect(OnboardingStep.photos.isBefore(OnboardingStep.appearanceType), isTrue);
      expect(OnboardingStep.idealConditions.isBefore(OnboardingStep.survey), isFalse);
      expect(OnboardingStep.bio.isBefore(OnboardingStep.avatar), isTrue);
      expect(OnboardingStep.avatar.isBefore(OnboardingStep.complete), isTrue);
    });

    test('같은 단계는 앞이 아니다', () {
      expect(OnboardingStep.kakaoId.isBefore(OnboardingStep.kakaoId), isFalse);
    });
  });
}
