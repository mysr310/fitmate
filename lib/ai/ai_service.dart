import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils.dart';
import '../providers.dart';
import 'ai_client.dart';
import 'parsers.dart';
import 'prompts.dart';

/// 食物识别服务（拍照 / 文字）
class FoodAiService {
  FoodAiService(this._ref);
  final Ref _ref;

  ({AiEndpoint endpoint, String model}) _requireVision() {
    final slots = _ref.read(aiSlotServiceProvider);
    final endpoint = slots.endpointFor(AiSlotService.slotVision);
    final model = slots.modelFor(AiSlotService.slotVision);
    if (endpoint == null || model == null) {
      throw AiException('尚未配置「食物识别」AI 模型，请到 我的 → AI 配置 完成设置');
    }
    return (endpoint: endpoint, model: model);
  }

  Future<FoodAiResult> analyzePhoto(Uint8List bytes, {String mime = 'image/jpeg'}) async {
    final (endpoint: endpoint, model: model) = _requireVision();
    final client = _ref.read(aiClientProvider);
    final b64 = base64Encode(bytes);
    final raw = await client.chat(
      endpoint: endpoint,
      model: model,
      messages: [
        AiMessage.system(Prompts.foodVisionSystem),
        AiMessage.userWithImage(Prompts.foodVisionUser, b64, mime: mime),
      ],
      jsonMode: true,
      temperature: 0.2,
      timeoutSeconds: 120,
    );
    return parseFoodAi(raw);
  }

  Future<FoodAiResult> analyzeText(String text) async {
    final (endpoint: endpoint, model: model) = _requireVision();
    final client = _ref.read(aiClientProvider);
    final raw = await client.chat(
      endpoint: endpoint,
      model: model,
      messages: [
        AiMessage.system(Prompts.foodTextSystem),
        AiMessage.userText('我的这一餐：$text'),
      ],
      jsonMode: true,
      temperature: 0.2,
      timeoutSeconds: 60,
    );
    return parseFoodAi(raw);
  }
}

/// 计划生成参数
class PlanGenParams {
  final int daysPerWeek;
  final int minutesPerSession;
  final String levelLabel; // 新手 / 有一定基础 / 高级
  final String equipment;
  final String preference;

  const PlanGenParams({
    required this.daysPerWeek,
    required this.minutesPerSession,
    required this.levelLabel,
    required this.equipment,
    required this.preference,
  });
}

/// 周计划生成服务
class PlanAiService {
  PlanAiService(this._ref);
  final Ref _ref;

  Future<WeeklyPlanAi> generate(PlanGenParams p) async {
    final slots = _ref.read(aiSlotServiceProvider);
    final endpoint = slots.endpointFor(AiSlotService.slotPlan);
    final model = slots.modelFor(AiSlotService.slotPlan);
    if (endpoint == null || model == null) {
      throw AiException('尚未配置「计划生成」AI 模型，请到 我的 → AI 配置 完成设置');
    }
    final profile = await _ref.read(profileProvider.future);
    if (profile == null) {
      throw AiException('请先完成 身体档案 填写');
    }
    // B2：每次生成时现算近 7 天平均摄入（不缓存，跨日/新增记录都能反映）
    final db = _ref.read(databaseProvider);
    final recent = await db.getFoodEntriesRange(lastNDays(7));
    final avgKcal = recent.isEmpty ? 0.0 : recent.fold<double>(0, (s, e) => s + e.kcal) / 7;
    // B3：使用最新体重（而非建档时的冗余字段）与中文目标描述
    final latestWeight = await db.latestWeight() ?? profile.weightKg;
    final trend = await _ref.read(weightTrendProvider.future);
    final sex = profile.sex == 'male' ? '男' : '女';

    final client = _ref.read(aiClientProvider);
    final raw = await client.chat(
      endpoint: endpoint,
      model: model,
      messages: [
        AiMessage.system(Prompts.planSystem),
        AiMessage.userText(Prompts.planUserContext(
          sex: sex,
          age: profile.age,
          heightCm: profile.heightCm,
          weightKg: latestWeight,
          targetWeightKg: profile.targetWeightKg,
          goalLabel: goalFrom(profile.goal).label,
          levelLabel: p.levelLabel,
          equipment: p.equipment,
          daysPerWeek: p.daysPerWeek,
          minutesPerSession: p.minutesPerSession,
          avgKcal7d: avgKcal,
          weightTrend: trend,
          preference: p.preference,
        )),
      ],
      jsonMode: true,
      temperature: 0.7,
      timeoutSeconds: 180,
    );
    return parseWeeklyPlanAi(raw);
  }
}

final aiClientProvider = Provider<AiClient>((ref) => AiClient(Dio()));
final foodAiServiceProvider = Provider<FoodAiService>((ref) => FoodAiService(ref));
final planAiServiceProvider = Provider<PlanAiService>((ref) => PlanAiService(ref));
