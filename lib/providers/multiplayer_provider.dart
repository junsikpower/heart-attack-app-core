import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';
import '../services/agora_service.dart';
import '../services/data_harvesting_service.dart';
import '../services/repositories/i_multiplayer_repository.dart';
import '../services/repositories/i_voice_chat_repository.dart';
import '../services/repositories/i_data_harvesting_repository.dart';

// ── 멀티플레이 상태 모델 ──
class MultiplayerState {
  final int opponentBpm;       // 상대방 심박수 (Firebase에서 실시간 수신)
  final String? roomId;        // 현재 방 코드
  final bool isConnected;      // 통화 연결 여부
  final bool isMuted;          // 마이크 음소거 여부
  final String errorMessage;

  const MultiplayerState({
    this.opponentBpm = 0,
    this.roomId,
    this.isConnected = false,
    this.isMuted = false,
    this.errorMessage = '',
  });

  MultiplayerState copyWith({
    int? opponentBpm,
    String? roomId,
    bool? isConnected,
    bool? isMuted,
    String? errorMessage,
  }) {
    return MultiplayerState(
      opponentBpm: opponentBpm ?? this.opponentBpm,
      roomId: roomId ?? this.roomId,
      isConnected: isConnected ?? this.isConnected,
      isMuted: isMuted ?? this.isMuted,
      errorMessage: errorMessage ?? '',
    );
  }
}

// ── 의존성 주입: 실제 구현체를 여기서 교체 ──
// 나중에 자체 서버로 바꿀 때 아래 줄만 교체하면 됨
final multiplayerRepoProvider = Provider<IMultiplayerRepository>((ref) {
  return FirebaseMultiplayerServiceImpl();
});

final voiceChatRepoProvider = Provider<IVoiceChatRepository>((ref) {
  return AgoraVoiceChatServiceImpl();
});

final dataHarvestingRepoProvider = Provider<IDataHarvestingRepository>((ref) {
  return FirestoreDataHarvestingServiceImpl();
});

// ── 멀티플레이 서비스 프로바이더 ──
final multiplayerProvider =
    StateNotifierProvider<MultiplayerService, MultiplayerState>((ref) {
  final multiRepo = ref.watch(multiplayerRepoProvider);
  final voiceRepo = ref.watch(voiceChatRepoProvider);
  final harvestRepo = ref.watch(dataHarvestingRepoProvider);
  return MultiplayerService(multiRepo, voiceRepo, harvestRepo);
});

// ── 멀티플레이 서비스 로직 ──
class MultiplayerService extends StateNotifier<MultiplayerState> {
  final IMultiplayerRepository _multiRepo;
  final IVoiceChatRepository _voiceRepo;
  // 🚫 하베스팅 중단으로 미사용 (임시 주석)
  // final IDataHarvestingRepository _harvestRepo;

  MultiplayerService(this._multiRepo, this._voiceRepo, IDataHarvestingRepository harvestRepo)
      : super(const MultiplayerState());

  // ── 방 생성 (호스트) ──
  Future<String> createRoom({
    required String userId,
    required int Function() myBpmGetter,
  }) async {
    try {
      final roomId = await _multiRepo.createRoom(userId);

      // 상대방 BPM 스트림 구독
      _multiRepo.opponentBpmStream.listen((bpm) {
        state = state.copyWith(opponentBpm: bpm);
      });

      // Agora 음성 채널 입장 (마이크 100% 독점 획득)
      await _voiceRepo.joinChannel(roomId);

      // 🚫 [하드웨어 충돌 원흉 봉인] STT 마이크 가로채기 방지를 위해 하베스팅 기능 임시 중단
      // 향후 Agora AudioFrameObserver + Cloud STT 아키텍처로 구현 예정
      // await _harvestRepo.startHarvesting(
      //   roomId: roomId,
      //   myUserId: userId,
      //   myBpmGetter: myBpmGetter,
      //   opponentBpmGetter: () => state.opponentBpm,
      // );

      state = state.copyWith(roomId: roomId, isConnected: true);
      return roomId;
    } catch (e) {
      state = state.copyWith(errorMessage: '방 생성 실패: $e');
      rethrow;
    }
  }

  // ── 방 참가 (게스트) ──
  Future<void> joinRoom({
    required String roomCode,
    required String userId,
    required int Function() myBpmGetter,
  }) async {
    try {
      await _multiRepo.joinRoom(roomCode, userId);

      // 상대방 BPM 스트림 구독
      _multiRepo.opponentBpmStream.listen((bpm) {
        state = state.copyWith(opponentBpm: bpm);
      });

      // Agora 음성 채널 입장 (마이크 100% 독점 획득)
      await _voiceRepo.joinChannel(roomCode);

      // 🚫 [하드웨어 충돌 원흉 봉인] STT 마이크 가로채기 방지를 위해 하베스팅 기능 임시 중단
      // 향후 Agora AudioFrameObserver + Cloud STT 아키텍처로 구현 예정
      // await _harvestRepo.startHarvesting(
      //   roomId: roomCode,
      //   myUserId: userId,
      //   myBpmGetter: myBpmGetter,
      //   opponentBpmGetter: () => state.opponentBpm,
      // );

      state = state.copyWith(roomId: roomCode, isConnected: true);
    } catch (e) {
      state = state.copyWith(errorMessage: '방 참가 실패: $e');
      rethrow;
    }
  }

  // ── 내 심박수 동기화 (게임 루프에서 주기적으로 호출) ──
  Future<void> syncMyBpm(int bpm) async {
    await _multiRepo.pushMyBpm(bpm);
  }

  // ── 마이크 음소거 토글 ──
  Future<void> toggleMute() async {
    await _voiceRepo.toggleMute();
    state = state.copyWith(isMuted: _voiceRepo.isMuted);
  }

  // ── 통화 종료 ──
  Future<void> disconnect() async {
    // 🚫 [봉인] 하베스팅 비활성화 중이므로 stopHarvesting도 주석 처리
    // await _harvestRepo.stopHarvesting();
    await _voiceRepo.leaveChannel();
    await _multiRepo.leaveRoom();
    state = const MultiplayerState();
  }
}
