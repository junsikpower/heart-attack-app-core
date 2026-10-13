// 음성 통화 서비스 (Agora) — 영상 없이 목소리만 주고받는다.
// 기존 AgoraVoiceChatServiceImpl의 안정화 로직(중복 입장 방지, 스피커폰 고정)을 유지하고,
// '누가 말하고 있는지' 보여주기 위한 음량 표시(Volume Indication) 스트림을 추가했다.

import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';

/// 말소리 크기 (0.0 ~ 1.0)
@immutable
class VoiceLevels {
  final double mine;
  final double theirs;
  const VoiceLevels({this.mine = 0, this.theirs = 0});
}

abstract class VoiceService {
  Stream<VoiceLevels> get levels;
  bool get isMuted;
  Future<void> join(String roomCode);
  Future<void> leave();
  Future<bool> toggleMute();
}

class AgoraVoiceService implements VoiceService {
  RtcEngine? _engine;
  Future<void>? _initFuture;
  String? _channel;
  bool _muted = false;
  double _mine = 0, _theirs = 0;

  final StreamController<VoiceLevels> _levels = StreamController<VoiceLevels>.broadcast();

  @override
  Stream<VoiceLevels> get levels => _levels.stream;

  @override
  bool get isMuted => _muted;

  Future<void> _ensureEngine() => _initFuture ??= _init();

  Future<void> _init() async {
    final appId = dotenv.env['AGORA_APP_ID'] ?? '';
    if (appId.isEmpty) throw Exception('AGORA_APP_ID가 .env에 없습니다.');
    try {
      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: appId));
      await engine.enableAudio();
      await engine.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );
      await engine.setDefaultAudioRouteToSpeakerphone(true);

      // 200ms마다 음량 보고 → 말하는 사람 캐릭터 주변에 파동 표시
      await engine.enableAudioVolumeIndication(interval: 200, smooth: 3, reportVad: true);
      engine.registerEventHandler(RtcEngineEventHandler(
        onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
          for (final s in speakers) {
            final level = ((s.volume ?? 0) / 255.0).clamp(0.0, 1.0);
            if ((s.uid ?? 0) == 0) {
              _mine = _muted ? 0 : level; // uid 0 = 나
            } else {
              _theirs = level;
            }
          }
          if (!_levels.isClosed) _levels.add(VoiceLevels(mine: _mine, theirs: _theirs));
        },
      ));
      _engine = engine;
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  @override
  Future<void> join(String roomCode) async {
    final channel = 'heartattack_$roomCode';
    if (_channel == channel) return;
    if (_channel != null) await leave();

    final status = await Permission.microphone.request();
    if (!status.isGranted) throw Exception('마이크 권한이 필요해요. 설정에서 허용해 주세요.');

    await _ensureEngine();
    await _engine!.joinChannel(
      token: '',
      channelId: channel,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        publishCameraTrack: false,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: false,
      ),
    );
    _channel = channel;
  }

  @override
  Future<void> leave() async {
    if (_engine == null || _channel == null) return;
    try {
      await _engine!.leaveChannel();
    } catch (e) {
      debugPrint('[Voice] 퇴장 오류 (무시됨): $e');
    }
    _channel = null;
    _muted = false;
    _mine = 0;
    _theirs = 0;
    if (!_levels.isClosed) _levels.add(const VoiceLevels());
  }

  @override
  Future<bool> toggleMute() async {
    _muted = !_muted;
    await _engine?.muteLocalAudioStream(_muted);
    return _muted;
  }
}
