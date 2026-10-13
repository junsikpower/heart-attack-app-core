// 내 프로필 (닉네임 + 하트 버디 색)
// 사진·나이·성별·지역은 받지 않는다. → 외모/조건이 아닌 '대화'로만 노는 게임.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class Profile {
  final String uid; // 기기마다 한 번 생성되는 익명 ID
  final String nickname;
  final int colorIndex; // AppColors.buddies 인덱스

  const Profile({required this.uid, required this.nickname, required this.colorIndex});

  Profile copyWith({String? nickname, int? colorIndex}) => Profile(
    uid: uid,
    nickname: nickname ?? this.nickname,
    colorIndex: colorIndex ?? this.colorIndex,
  );
}

/// main()에서 미리 로드한 SharedPreferences를 주입받는다.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main()에서 override 필요'),
);

class ProfileNotifier extends StateNotifier<Profile?> {
  ProfileNotifier(this._prefs) : super(null) {
    _load();
  }

  final SharedPreferences _prefs;
  static const _kUid = 'profile.uid';
  static const _kNick = 'profile.nickname';
  static const _kColor = 'profile.color';

  void _load() {
    var uid = _prefs.getString(_kUid);
    if (uid == null) {
      uid = _randomId();
      _prefs.setString(_kUid, uid);
    }
    final nick = _prefs.getString(_kNick);
    _uid = uid;
    if (nick != null && nick.isNotEmpty) {
      state = Profile(uid: uid, nickname: nick, colorIndex: _prefs.getInt(_kColor) ?? 0);
    }
  }

  late final String _uid;

  /// 아직 닉네임을 정하지 않았다면 null
  bool get hasProfile => state != null;

  Future<void> save({required String nickname, required int colorIndex}) async {
    final trimmed = nickname.trim();
    await _prefs.setString(_kNick, trimmed);
    await _prefs.setInt(_kColor, colorIndex);
    state = Profile(uid: _uid, nickname: trimmed, colorIndex: colorIndex);
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = math.Random.secure();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

final profileProvider = StateNotifierProvider<ProfileNotifier, Profile?>(
  (ref) => ProfileNotifier(ref.watch(sharedPrefsProvider)),
);

/// 닉네임 추천 (처음 실행 시 기본값)
String suggestNickname() {
  const a = ['수줍은', '용감한', '느긋한', '반짝이는', '말랑한', '엉뚱한', '다정한', '씩씩한'];
  const b = ['고양이', '판다', '수달', '토끼', '펭귄', '여우', '햄스터', '다람쥐'];
  final r = math.Random();
  return '${a[r.nextInt(a.length)]} ${b[r.nextInt(b.length)]}';
}
