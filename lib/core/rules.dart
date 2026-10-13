// 게임 규칙 (Game Rules) — "두근 배틀"
// 이 파일은 화면/네트워크와 무관한 '순수 규칙'만 담는다. (단위 테스트 대상: test/rules_test.dart)
//
// ┌─ 한 판의 흐름 ──────────────────────────────────────────────┐
// │ 1. 숨 고르기 (15초) : 둘 다 조용히 → 각자의 '기준 심박' 측정        │
// │ 2. 3라운드 × 2턴 = 총 6턴 (공격/방어를 번갈아 맡음)               │
// │    - 카드 고르기 (10초) : 공격자가 카드 3장 중 1장 선택             │
// │    - 공격 (30초)       : 공격자는 카드대로 말하고, 방어자는 듣기만   │
// │                         → '방어자'의 심박만 점수로 계산           │
// │    - 결과 공개 (4초)    : 이번 턴에 공격자가 얻은 점수 공개          │
// │ 3. 총점이 높은 사람이 승리                                    │
// └──────────────────────────────────────────────────────────┘
//
// 왜 '듣는 사람만' 재는가?
//   말하는 행위 자체가 화자의 심박을 올리기 때문에(호흡·긴장·움직임),
//   말하는 사람을 재면 '설렘'과 '말하기'가 섞인다. 듣는 사람은 손도 가만히 있어 측정도 정확하다.

import 'dart:math' as math;

class GameRules {
  GameRules._();

  // ── 시간 (초) ──
  static const int calibrateSeconds = 15; // 숨 고르기 (기준 심박 측정)
  static const int pickSeconds = 10; // 카드 고르기
  static const int attackSeconds = 30; // 공격 (방어자 심박 측정)
  static const int revealSeconds = 4; // 턴 결과 공개
  static const int lobbyReadyHoldSeconds = 3; // 둘 다 준비된 뒤 자동 시작까지 대기

  // ── 판 구성 ──
  static const int rounds = 3;
  static const int turnsPerRound = 2;
  static const int totalTurns = rounds * turnsPerRound; // 6턴

  // ── 점수 ──
  /// 1초당 인정하는 최대 상승률(%). 측정 튐(노이즈) 한 번으로 승부가 갈리지 않도록 상한을 둔다.
  static const double maxRisePercentPerSecond = 30.0;

  /// 손가락을 떼도 봐주는 시간(초). 자세를 고쳐 잡는 정도는 허용한다.
  static const int hideGraceSeconds = 3;

  /// 유예 시간을 넘겨 손을 떼고 있으면, 1초마다 공격자에게 주는 점수 ('숨긴 걸로 간주').
  static const double hidePenaltyPerSecond = 10.0;

  /// 기준 심박을 확정하는 데 필요한 최소 측정 샘플 수 (1초에 1개)
  static const int minBaselineSamples = 3;

  /// 전체 한 판 예상 시간 (초) — 안내 문구용
  static int get estimatedMatchSeconds =>
      calibrateSeconds + totalTurns * (pickSeconds + attackSeconds + revealSeconds);

  /// n번째 턴(0부터)의 공격자가 호스트인지 여부.
  /// 호스트 → 게스트 → 호스트 … 순서로 번갈아 공격한다.
  static bool isHostAttacker(int turnIndex) => turnIndex.isEven;

  /// n번째 턴이 몇 라운드인지 (1부터)
  static int roundOf(int turnIndex) => turnIndex ~/ turnsPerRound + 1;

  /// 기준 대비 상승률(%) = (현재 - 기준) / 기준 × 100
  static double risePercent({required double bpm, required double baseline}) {
    if (baseline <= 0 || bpm <= 0) return 0;
    return (bpm - baseline) / baseline * 100.0;
  }

  /// 공격 중 1초 동안 공격자가 얻는 점수.
  /// - 방어자 심박이 기준보다 높았던 만큼(%) 점수 (0 ~ 30점)
  /// - 기준보다 낮으면 0점 (마이너스 없음)
  static double pointsForSecond({required double bpm, required double baseline}) {
    final rise = risePercent(bpm: bpm, baseline: baseline);
    return rise.clamp(0.0, maxRisePercentPerSecond).toDouble();
  }

  /// 손을 뗀 누적 시간(초)에 따른 이번 1초의 페널티 점수.
  /// [lostSecondsSoFar]는 이번 1초를 포함한 누적값.
  static double hidePenaltyForSecond(int lostSecondsSoFar) =>
      lostSecondsSoFar > hideGraceSeconds ? hidePenaltyPerSecond : 0.0;

  /// 기준 심박 = 숨 고르기 동안 측정한 값들의 평균. 샘플이 부족하면 null.
  static double? baselineFrom(List<double> samples) {
    final valid = samples.where((b) => b > 0).toList();
    if (valid.length < minBaselineSamples) return null;
    return valid.reduce((a, b) => a + b) / valid.length;
  }

  /// 공격자 화면에 보여주는 '두근 미터' 단계 (0~4).
  /// 상대의 정확한 숫자 대신 단계만 보여줘서 긴장감을 만든다.
  static int dokiLevel(double risePercent) {
    if (risePercent >= 15) return 4;
    if (risePercent >= 10) return 3;
    if (risePercent >= 5) return 2;
    if (risePercent >= 2) return 1;
    return 0;
  }

  static const dokiLabels = ['잔잔', '살랑', '두근', '쿵쾅', '심쿵!'];

  /// 최종 승패: 1 = 내가 승, -1 = 패, 0 = 무승부
  static int compareScores(int mine, int theirs) => (mine - theirs).sign;

  /// 점수 반올림 (화면 표시/저장용 정수)
  static int roundPoints(double points) => math.max(0, points.round());
}
