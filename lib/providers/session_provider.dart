// 멀티플레이 세션 컨트롤러 (게임 진행의 두뇌)
//
// 역할 분담 — "호스트는 시계, 방어자는 채점관"
//   • 호스트(방을 만든 사람): 페이즈 진행만 담당. 시간이 다 되면 다음 페이즈로 넘긴다.
//       숨 고르기 → [카드 고르기 → 공격 → 결과 공개] × 6턴 → 최종 결과
//   • 방어자(이번 턴에 듣는 사람): 자기 폰에서 잰 자기 심박으로 공격자의 점수를 매초 계산해 기록한다.
//       → 심박 원본이 네트워크를 거치지 않아 지연·손실 없이 가장 정확하게 채점된다.
//   • 모든 플레이어: 1초마다 내 심박을 live/{uid}에 올린다 (상대 화면의 '두근 미터'용).
//
// 두 폰의 타이머는 Firebase 서버 시각(serverTimeOffset) 기준으로 맞춘다.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/cards.dart';
import '../core/rules.dart';
import '../heart/heart_rate_source.dart';
import '../multiplayer/room_models.dart';
import '../multiplayer/room_repository.dart';
import '../multiplayer/voice_service.dart';
import 'heart_rate_provider.dart';
import 'profile_provider.dart';

final roomRepositoryProvider = Provider<RoomRepository>((ref) => FirebaseRoomRepository());
final voiceServiceProvider = Provider<VoiceService>((ref) => AgoraVoiceService());
final voiceLevelsProvider = StreamProvider<VoiceLevels>(
  (ref) => ref.watch(voiceServiceProvider).levels,
);

@immutable
class SessionState {
  final String? code; // 현재 방 코드 (null이면 방 밖)
  final RoomSnapshot? room;
  final int serverOffset;
  final String? abortReason; // 상대 이탈 등으로 게임을 이어갈 수 없을 때
  final bool muted;
  final String? voiceError;

  const SessionState({
    this.code,
    this.room,
    this.serverOffset = 0,
    this.abortReason,
    this.muted = false,
    this.voiceError,
  });

  SessionState copyWith({
    RoomSnapshot? room,
    int? serverOffset,
    String? abortReason,
    bool? muted,
    String? voiceError,
  }) => SessionState(
    code: code,
    room: room ?? this.room,
    serverOffset: serverOffset ?? this.serverOffset,
    abortReason: abortReason ?? this.abortReason,
    muted: muted ?? this.muted,
    voiceError: voiceError ?? this.voiceError,
  );
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(const SessionState()) {
    _offsetSub = _repo.serverTimeOffset().listen((o) {
      if (mounted) state = state.copyWith(serverOffset: o);
    });
  }

  final Ref _ref;
  RoomRepository get _repo => _ref.read(roomRepositoryProvider);
  VoiceService get _voice => _ref.read(voiceServiceProvider);
  HeartRateNotifier get _heart => _ref.read(heartRateProvider.notifier);

  StreamSubscription<int>? _offsetSub;
  StreamSubscription<RoomSnapshot?>? _roomSub;
  Timer? _clientTimer;
  Timer? _hostTimer;
  bool _hostBusy = false;
  bool? _measuringWanted;

  // ── 호스트 전용 기록 ──
  int? _bothReadySince;
  int? _guestOfflineSince;

  // ── 내 폰의 로컬 채점 기록 ──
  int? _localGameId;
  final List<double> _calibSamples = [];
  double? _lazyBaseline;
  int? _defendingTurn;
  double _turnPoints = 0;
  double _peakRise = 0;
  int _lostSeconds = 0;
  final List<int> _riseSamples = [];
  int? _opponentOfflineSince;

  Profile get _me {
    final p = _ref.read(profileProvider);
    if (p == null) throw const RoomException('닉네임을 먼저 정해 주세요.');
    return p;
  }

  String get myUid => _me.uid;

  /// 서버 기준 현재 시각(ms) — 두 폰이 같은 타이머를 보도록
  int get serverNow => DateTime.now().millisecondsSinceEpoch + state.serverOffset;

  // ─────────────────────────────────────────────
  // 입장 / 퇴장
  // ─────────────────────────────────────────────
  Future<void> createRoom() async {
    final code = await _repo.createRoom(_me);
    await _enter(code);
  }

  Future<void> joinRoom(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    await _repo.joinRoom(code, _me);
    await _enter(code);
  }

  /// 빠른 매칭. 취소되면 false.
  Future<bool> quickMatch() async {
    final found = await _repo.quickMatch(_me);
    if (found == null) return false;
    if (!found.asHost) await _repo.joinRoom(found.code, _me);
    await _enter(found.code);
    return true;
  }

  Future<void> cancelQuickMatch() => _repo.cancelQuickMatch();

  Future<void> _enter(String code) async {
    await _stopTimers();
    _resetLocalScoring();
    _bothReadySince = null;
    _guestOfflineSince = null;
    _opponentOfflineSince = null;
    _measuringWanted = null;
    state = SessionState(code: code, serverOffset: state.serverOffset);

    _roomSub = _repo.watchRoom(code).listen(_onRoom);
    await _repo.markOnline(code, myUid);
    _clientTimer = Timer.periodic(const Duration(seconds: 1), (_) => _clientTick());
    _hostTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => _hostStep());

    // 음성 연결은 실패해도 게임 자체는 진행되도록 오류만 표시한다
    try {
      await _voice.join(code);
    } catch (e) {
      if (mounted) state = state.copyWith(voiceError: '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> leave() async {
    final code = state.code;
    final room = state.room;
    await _stopTimers();
    if (code != null) {
      try {
        await _repo.leaveRoom(
          code,
          myUid,
          isHost: room?.isHost(myUid) ?? false,
          status: room?.status ?? RoomStatus.lobby,
        );
      } catch (e) {
        debugPrint('[Session] 퇴장 기록 실패: $e');
      }
    }
    await _voice.leave();
    await _heart.stop();
    _measuringWanted = null;
    if (mounted) state = SessionState(serverOffset: state.serverOffset);
  }

  Future<void> _stopTimers() async {
    _clientTimer?.cancel();
    _hostTimer?.cancel();
    _clientTimer = null;
    _hostTimer = null;
    await _roomSub?.cancel();
    _roomSub = null;
  }

  // ─────────────────────────────────────────────
  // 플레이어 행동
  // ─────────────────────────────────────────────
  Future<void> pickCard(String cardId) async {
    final room = state.room;
    final game = room?.game;
    if (room == null || game == null) return;
    if (game.phase != GamePhase.pick || game.attackerId != myUid || game.cardId != null) return;
    await _repo.pickCard(room.code, cardId);
  }

  Future<void> toggleMute() async {
    final muted = await _voice.toggleMute();
    if (mounted) state = state.copyWith(muted: muted);
  }

  /// 한 판 더 — 둘 다 누르면 호스트가 새 판을 시작한다
  Future<void> requestRematch() async {
    final code = state.code;
    if (code == null) return;
    await _repo.updatePlayer(code, myUid, {'rematch': true});
  }

  // ─────────────────────────────────────────────
  // 방 데이터 수신
  // ─────────────────────────────────────────────
  void _onRoom(RoomSnapshot? room) {
    if (!mounted) return;
    if (room == null) {
      state = state.copyWith(abortReason: '방이 사라졌어요.');
      return;
    }
    state = state.copyWith(room: room);

    if (room.status == RoomStatus.closed && !room.isHost(myUid)) {
      state = state.copyWith(abortReason: '상대가 방을 닫았어요.');
    }
    _syncMeasurement(room);
  }

  /// 플래시는 꼭 필요할 때만 켠다 (발열 최소화)
  ///   대기실: 상대가 들어왔을 때만 / 게임 중: 항상 / 결과 화면: '한 판 더'를 눌렀을 때만
  void _syncMeasurement(RoomSnapshot room) {
    final wants = switch (room.status) {
      RoomStatus.lobby => room.isFull,
      RoomStatus.playing => room.game?.phase != GamePhase.result,
      RoomStatus.finished => room.player(myUid)?.rematch ?? false,
      RoomStatus.closed => false,
    };
    if (wants == _measuringWanted) return;
    _measuringWanted = wants;
    wants ? _heart.start() : _heart.stop();
  }

  // ─────────────────────────────────────────────
  // 1초마다: 내 심박 공유 + 준비 상태 + 기준 심박 + (방어 중이면) 채점
  // ─────────────────────────────────────────────
  void _clientTick() {
    final room = state.room;
    final code = state.code;
    if (room == null || code == null || !mounted) return;
    final heart = _ref.read(heartRateProvider);
    final me = myUid;

    if (heart.isMeasuring) {
      _repo.pushLive(code, me, bpm: heart.bpm.round(), ok: heart.isValid);
    }

    switch (room.status) {
      case RoomStatus.lobby:
        final ready = heart.isValid;
        if (room.player(me)?.ready != ready) {
          _repo.updatePlayer(code, me, {'ready': ready});
        }
      case RoomStatus.playing:
        _checkOpponentPresence(room);
        _playingTick(room, code, heart);
      case RoomStatus.finished:
      case RoomStatus.closed:
        break;
    }
  }

  void _checkOpponentPresence(RoomSnapshot room) {
    final opponent = room.player(room.opponentOf(myUid));
    if (opponent == null || opponent.online) {
      _opponentOfflineSince = null;
      return;
    }
    _opponentOfflineSince ??= serverNow;
    if (serverNow - _opponentOfflineSince! > 8000 && state.abortReason == null) {
      state = state.copyWith(abortReason: '상대의 연결이 끊겼어요.');
    }
  }

  void _resetLocalScoring() {
    _calibSamples.clear();
    _lazyBaseline = null;
    _defendingTurn = null;
    _turnPoints = 0;
    _peakRise = 0;
    _lostSeconds = 0;
    _riseSamples.clear();
  }

  void _playingTick(RoomSnapshot room, String code, HeartRateState heart) {
    final game = room.game;
    if (game == null) return;
    if (game.gameId != _localGameId) {
      _localGameId = game.gameId;
      _resetLocalScoring();
    }

    switch (game.phase) {
      case GamePhase.calibrate:
        // 숨 고르기: 유효한 측정값을 모아 평균을 기준 심박으로 올린다
        if (heart.isValid) {
          _calibSamples.add(heart.bpm);
          final baseline = GameRules.baselineFrom(_calibSamples);
          if (baseline != null) _repo.setBaseline(code, myUid, baseline);
        }
      case GamePhase.attack:
        if (room.defenderOfTurn(game.turn) == myUid) _defendTick(room, code, game, heart);
      case GamePhase.pick:
      case GamePhase.reveal:
      case GamePhase.result:
        break;
    }
  }

  /// 방어자 채점: 1초마다 내 심박 상승률만큼 공격자에게 점수를 준다
  void _defendTick(RoomSnapshot room, String code, GameState game, HeartRateState heart) {
    final me = myUid;
    if (_defendingTurn != game.turn) {
      _defendingTurn = game.turn;
      _turnPoints = 0;
      _peakRise = 0;
      _lostSeconds = 0;
      _riseSamples.clear();
    }

    // 숨 고르기 때 기준 심박을 못 잡았으면, 처음 잡히는 값을 기준으로 삼는다
    var baseline = room.baselines[me] ?? _lazyBaseline;
    if (baseline == null && heart.isValid) {
      baseline = heart.bpm;
      _lazyBaseline = baseline;
      _repo.setBaseline(code, me, baseline);
    }

    if (heart.isValid && baseline != null) {
      final rise = GameRules.risePercent(bpm: heart.bpm, baseline: baseline);
      _turnPoints += GameRules.pointsForSecond(bpm: heart.bpm, baseline: baseline);
      _peakRise = math.max(_peakRise, rise);
      _lostSeconds = 0;
      _riseSamples.add(rise.round());
    } else {
      // 손가락을 떼서 신호가 끊긴 경우: 유예 시간이 지나면 '숨긴 걸로 간주'해 공격자 점수
      final lost = heart.signal == HeartSignal.lost ||
          heart.signal == HeartSignal.error ||
          heart.signal == HeartSignal.idle;
      if (lost) {
        _lostSeconds++;
        _turnPoints += GameRules.hidePenaltyForSecond(_lostSeconds);
      }
      _riseSamples.add(0);
    }

    _repo.writeTurn(
      code,
      TurnRecord(
        turn: game.turn,
        attackerId: game.attackerId ?? room.attackerOfTurn(game.turn) ?? '',
        defenderId: me,
        cardId: game.cardId,
        points: GameRules.roundPoints(_turnPoints),
        peakRise: math.max(0, _peakRise.round()),
        samples: List.of(_riseSamples),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 호스트: 페이즈 진행 (0.3초마다 확인)
  // ─────────────────────────────────────────────
  Future<void> _hostStep() async {
    final room = state.room;
    final code = state.code;
    if (room == null || code == null || _hostBusy || !mounted) return;
    if (!room.isHost(myUid)) return;
    _hostBusy = true;
    try {
      await _hostAdvance(room, code);
    } catch (e) {
      debugPrint('[Session] 호스트 진행 오류: $e');
    } finally {
      _hostBusy = false;
    }
  }

  Future<void> _hostAdvance(RoomSnapshot room, String code) async {
    final now = serverNow;
    switch (room.status) {
      case RoomStatus.lobby:
        final host = room.player(room.hostId);
        final guest = room.player(room.guestId);

        // 대기실에서 오래 끊긴 게스트는 자리를 비운다 (다른 사람이 들어올 수 있게)
        if (guest != null && !guest.online) {
          _guestOfflineSince ??= now;
          if (now - _guestOfflineSince! > 10000) {
            _guestOfflineSince = null;
            await _repo.updateRoom(code, {
              'guestId': null,
              'players/${guest.uid}': null,
              'live/${guest.uid}': null,
            });
          }
        } else {
          _guestOfflineSince = null;
        }

        // 둘 다 손가락 측정이 잡힌 상태로 3초 유지되면 자동 시작
        final bothReady = host != null && host.ready && guest != null && guest.online && guest.ready;
        if (!bothReady) {
          _bothReadySince = null;
          return;
        }
        _bothReadySince ??= now;
        if (now - _bothReadySince! >= GameRules.lobbyReadyHoldSeconds * 1000) {
          _bothReadySince = null;
          await _startGame(room, code, now);
        }

      case RoomStatus.playing:
        final game = room.game;
        if (game == null) return;
        final pickedEarly = game.phase == GamePhase.pick && game.cardId != null;
        if (now < game.endsAt && !pickedEarly) return;
        await _advancePhase(room, code, game, now);

      case RoomStatus.finished:
        final both = [room.player(room.hostId), room.player(room.guestId)];
        if (both.every((p) => p != null && p.online && p.rematch)) {
          await _startGame(room, code, now);
        }

      case RoomStatus.closed:
        break;
    }
  }

  Future<void> _startGame(RoomSnapshot room, String code, int now) async {
    await _repo.updateRoom(code, {
      'status': RoomStatus.playing.name,
      'baselines': null,
      'turns': null,
      'game': {
        'phase': GamePhase.calibrate.name,
        'turn': 0,
        'endsAt': now + GameRules.calibrateSeconds * 1000,
        'gameId': now,
        'choices': '',
      },
      'players/${room.hostId}/rematch': false,
      if (room.guestId != null) 'players/${room.guestId}/rematch': false,
    });
  }

  Future<void> _advancePhase(RoomSnapshot room, String code, GameState game, int now) async {
    switch (game.phase) {
      case GamePhase.calibrate:
        await _beginPick(room, code, 0, now);

      case GamePhase.pick:
        // 시간 안에 못 고르면 첫 번째 카드로 자동 선택
        final card = game.cardId ?? (game.choices.isNotEmpty ? game.choices.first : null);
        await _repo.updateRoom(code, {
          'game/phase': GamePhase.attack.name,
          'game/cardId': card,
          'game/endsAt': now + GameRules.attackSeconds * 1000,
        });

      case GamePhase.attack:
        final updates = <String, Object?>{
          'game/phase': GamePhase.reveal.name,
          'game/endsAt': now + GameRules.revealSeconds * 1000,
        };
        // 방어자 기록이 하나도 없다면(측정 실패) 0점 기록을 남겨 턴을 완결시킨다
        if (!room.turns.containsKey(game.turn)) {
          updates['turns/t${game.turn}'] = TurnRecord(
            turn: game.turn,
            attackerId: room.attackerOfTurn(game.turn) ?? '',
            defenderId: room.defenderOfTurn(game.turn) ?? '',
            cardId: game.cardId,
          ).toMap();
        }
        await _repo.updateRoom(code, updates);

      case GamePhase.reveal:
        final next = game.turn + 1;
        if (next < GameRules.totalTurns) {
          await _beginPick(room, code, next, now);
        } else {
          await _repo.updateRoom(code, {
            'game/phase': GamePhase.result.name,
            'game/endsAt': now,
            'status': RoomStatus.finished.name,
          });
        }

      case GamePhase.result:
        break;
    }
  }

  Future<void> _beginPick(RoomSnapshot room, String code, int turn, int now) async {
    final used = {...room.usedCards, ?room.game?.cardId};
    final choices = CardDeck.drawChoices(exclude: used);
    await _repo.updateRoom(code, {
      'game/phase': GamePhase.pick.name,
      'game/turn': turn,
      'game/attackerId': room.attackerOfTurn(turn),
      'game/choices': choices.map((c) => c.id).join(','),
      'game/cardId': null,
      'game/endsAt': now + GameRules.pickSeconds * 1000,
    });
  }

  @override
  void dispose() {
    _offsetSub?.cancel();
    _clientTimer?.cancel();
    _hostTimer?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref),
);
