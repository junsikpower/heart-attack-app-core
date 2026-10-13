// 스토리 모드(싱글플레이) — 이번 버전에서는 로비에서 누를 수 있는 입구만 제공한다.

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/heart_buddy.dart';

Future<void> showStoryComingSoon(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (context) => Container(
    padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + MediaQuery.of(context).padding.bottom),
    decoration: const BoxDecoration(
      color: AppColors.cream,
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(9)),
        ),
        const SizedBox(height: 20),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HeartBuddy(colorIndex: 5, size: 64, flush: 0.3),
            HeartBuddy(colorIndex: 1, size: 64, flush: 0.9),
            HeartBuddy(colorIndex: 3, size: 64),
          ],
        ),
        const SizedBox(height: 12),
        const Chip2('COMING SOON', color: AppColors.lilac, icon: Icons.lock_clock_rounded),
        const SizedBox(height: 10),
        Text('스토리 모드 준비 중', style: AppText.display(26)),
        const SizedBox(height: 8),
        Text(
          '개성 강한 캐릭터들과 1:1로 대화하며\n내 진짜 심박으로 이야기가 바뀌는 모드예요.\n조금만 기다려 주세요!',
          textAlign: TextAlign.center,
          style: AppText.body(14.5, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 22),
        BigButton(label: '기대할게요', secondary: true, onPressed: () => Navigator.pop(context)),
      ],
    ),
  ),
);
