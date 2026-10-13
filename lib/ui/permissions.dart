// 런타임 권한 요청 (Android 6+ / Galaxy One UI 공통)
// 게임에 들어가기 전에 카메라(심박 측정)와 마이크(음성 대화) 권한을 한 번에 받는다.
// '다시 묻지 않음'으로 거부된 경우에는 설정 화면으로 안내한다.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'widgets/common.dart';

Future<bool> ensureGamePermissions(BuildContext context) async {
  final results = await [Permission.camera, Permission.microphone].request();
  final camera = results[Permission.camera]!;
  final mic = results[Permission.microphone]!;
  if (camera.isGranted && mic.isGranted) return true;

  if (!context.mounted) return false;
  final permanentlyDenied = camera.isPermanentlyDenied || mic.isPermanentlyDenied;
  final missing = [if (!camera.isGranted) '카메라(심박 측정)', if (!mic.isGranted) '마이크(음성 대화)'];
  if (permanentlyDenied) {
    showToast(context, '${missing.join(', ')} 권한을 설정에서 허용해 주세요.');
    await openAppSettings();
  } else {
    showToast(context, '${missing.join(', ')} 권한이 있어야 플레이할 수 있어요.');
  }
  return false;
}
