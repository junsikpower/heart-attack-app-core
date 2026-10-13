// 게임 규칙 / 카드 덱 / 방 데이터 변환 단위 테스트

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:heart_attack_mvp_app/core/cards.dart';
import 'package:heart_attack_mvp_app/core/rules.dart';
import 'package:heart_attack_mvp_app/multiplayer/room_models.dart';

void main() {
  group('점수 규칙', () {
    test('기준 70 → 77이면 1초에 10점', () {
      expect(GameRules.pointsForSecond(bpm: 77, baseline: 70), closeTo(10, 0.001));
    });

    test('기준보다 낮으면 0점 (마이너스 없음)', () {
      expect(GameRules.pointsForSecond(bpm: 65, baseline: 70), 0);
    });

    test('1초 최대 30점 상한', () {
      expect(GameRules.pointsForSecond(bpm: 140, baseline: 70), GameRules.maxRisePercentPerSecond);
    });

    test('측정값/기준이 없으면 0점', () {
      expect(GameRules.pointsForSecond(bpm: 0, baseline: 70), 0);
      expect(GameRules.pointsForSecond(bpm: 80, baseline: 0), 0);
    });

    test('손 떼기 페널티: 유예 3초까지 0, 이후 10점', () {
      expect(GameRules.hidePenaltyForSecond(1), 0);
      expect(GameRules.hidePenaltyForSecond(3), 0);
      expect(GameRules.hidePenaltyForSecond(4), GameRules.hidePenaltyPerSecond);
    });

    test('기준 심박은 유효 샘플 3개 이상일 때 평균', () {
      expect(GameRules.baselineFrom([70, 72]), isNull);
      expect(GameRules.baselineFrom([70, 0, 72, 74]), closeTo(72, 0.001));
    });

    test('두근 미터 단계 경계값', () {
      expect(GameRules.dokiLevel(0), 0);
      expect(GameRules.dokiLevel(2), 1);
      expect(GameRules.dokiLevel(5), 2);
      expect(GameRules.dokiLevel(10), 3);
      expect(GameRules.dokiLevel(15), 4);
    });

    test('공격 순서: 호스트 → 게스트 번갈아, 3라운드 6턴', () {
      expect(GameRules.totalTurns, 6);
      expect([for (var t = 0; t < 6; t++) GameRules.isHostAttacker(t)],
          [true, false, true, false, true, false]);
      expect([for (var t = 0; t < 6; t++) GameRules.roundOf(t)], [1, 1, 2, 2, 3, 3]);
    });

    test('한 판 예상 시간은 5분 안팎', () {
      expect(GameRules.estimatedMatchSeconds, 15 + 6 * (10 + 30 + 4));
    });
  });

  group('카드 덱', () {
    test('카드 ID는 모두 고유', () {
      final ids = CardDeck.all.map((c) => c.id).toSet();
      expect(ids.length, CardDeck.all.length);
    });

    test('선택지 3장은 서로 다른 종류', () {
      for (var seed = 0; seed < 50; seed++) {
        final picks = CardDeck.drawChoices(random: math.Random(seed));
        expect(picks.length, 3);
        expect(picks.map((c) => c.kind).toSet().length, 3);
      }
    });

    test('이미 쓴 카드는 피한다', () {
      final used = CardDeck.all.where((c) => c.id != 'l1' && c.kind == CardKind.laugh).map((c) => c.id).toSet();
      for (var seed = 0; seed < 30; seed++) {
        final picks = CardDeck.drawChoices(exclude: used, random: math.Random(seed));
        for (final c in picks.where((c) => c.kind == CardKind.laugh)) {
          expect(c.id, 'l1');
        }
      }
    });
  });

  group('방 데이터 변환', () {
    final raw = <String, Object?>{
      'hostId': 'h',
      'guestId': 'g',
      'status': 'playing',
      'players': {
        'h': {'nickname': '호스트', 'color': 2, 'ready': true, 'online': true},
        'g': {'nickname': '게스트', 'color': 5, 'ready': true, 'online': false},
      },
      'live': {
        'g': {'bpm': 81, 'ok': true},
      },
      'baselines': {'h': 70.5, 'g': 75},
      'game': {'phase': 'attack', 'turn': 1, 'endsAt': 1000, 'attackerId': 'g', 'choices': 'l1,t2,w3', 'cardId': 't2', 'gameId': 7},
      'turns': {
        't0': {'attackerId': 'h', 'defenderId': 'g', 'cardId': 'l1', 'points': 120, 'peakRise': 14, 'samples': '0,5,9,14'},
        't1': {'attackerId': 'g', 'defenderId': 'h', 'cardId': 't2', 'points': 40, 'peakRise': 6, 'samples': '1,6'},
        't2': {'attackerId': 'h', 'defenderId': 'g', 'cardId': 'w3', 'points': 30, 'peakRise': 3, 'samples': ''},
      },
    };

    test('스냅샷 파싱', () {
      final room = RoomSnapshot.fromMap('ABCDE', raw);
      expect(room.status, RoomStatus.playing);
      expect(room.player('g')!.online, isFalse);
      expect(room.live['g']!.bpm, 81);
      expect(room.baselines['g'], 75);
      expect(room.game!.phase, GamePhase.attack);
      expect(room.game!.choices, ['l1', 't2', 'w3']);
      expect(room.turns[0]!.samples, [0, 5, 9, 14]);
      expect(room.turns[2]!.samples, isEmpty);
    });

    test('점수 합산 = 내가 공격자였던 턴의 합', () {
      final room = RoomSnapshot.fromMap('ABCDE', raw);
      expect(room.scoreOf('h'), 150);
      expect(room.scoreOf('g'), 40);
    });

    test('턴별 공격/방어자', () {
      final room = RoomSnapshot.fromMap('ABCDE', raw);
      expect(room.attackerOfTurn(0), 'h');
      expect(room.defenderOfTurn(1), 'h');
      expect(room.currentDefender, 'h');
      expect(room.usedCards, {'l1', 't2', 'w3'});
    });

    test('턴 기록 직렬화 왕복', () {
      const rec = TurnRecord(turn: 3, attackerId: 'g', defenderId: 'h', cardId: 'f1', points: 88, peakRise: 12, samples: [1, 2, 3]);
      final back = TurnRecord.fromMap(3, rec.toMap());
      expect(back.points, 88);
      expect(back.samples, [1, 2, 3]);
    });
  });
}
