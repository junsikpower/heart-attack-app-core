// 게임 중 공통 대화상자 / 안내 오버레이

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'common.dart';

Future<bool> confirmLeave(BuildContext context, {String message = '지금 나가면 이번 판은 끝나요.'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text('나갈까요?', style: AppText.display(24)),
      content: Text(message, style: AppText.body(15, color: AppColors.inkSoft)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('계속하기', style: AppText.body(15, weight: FontWeight.w700)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('나가기', style: AppText.body(15, color: AppColors.coral, weight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 상대 이탈 등으로 게임을 이어갈 수 없을 때 화면 전체를 덮는 안내
class AbortOverlay extends StatelessWidget {
  final String reason;
  final VoidCallback onExit;
  const AbortOverlay({super.key, required this.reason, required this.onExit});

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Container(
      color: AppColors.cream.withValues(alpha: 0.96),
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.inkFaint),
          const SizedBox(height: 16),
          Text(reason, textAlign: TextAlign.center, style: AppText.display(24)),
          const SizedBox(height: 24),
          SizedBox(width: 200, child: BigButton(label: '로비로', onPressed: onExit)),
        ],
      ),
    ),
  );
}
