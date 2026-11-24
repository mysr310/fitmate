import 'package:dio/dio.dart';

/// AI 接口档案的轻量引用（避免 UI 层依赖数据库对象）
class AiEndpoint {
  final String name;
  final String baseUrl;
  final String apiKey;

  const AiEndpoint({required this.name, required this.baseUrl, required this.apiKey});

  factory AiEndpoint.fromJson(Map<String, dynamic> j) => AiEndpoint(
        name: (j['name'] ?? '') as String,
        baseUrl: (j['base_url'] ?? '') as String,
        apiKey: (j['api_key'] ?? '') as String,
      );
}

/// 单条消息（content 为 String 或 part 列表）
class AiMessage {
  final String role;
  final dynamic content;

  AiMessage.system(String text) : this._('system', text);
  AiMessage.user(dynamic content) : this._('user', content);

  AiMessage._(this.role, this.content);

  /// 纯文本用户消息
  static AiMessage userText(String text) => AiMessage._('user', text);

  /// 图文混合消息（base64 图片，不带 data: 前缀）
  static AiMessage userWithImage(String text, String base64Image, {String mime = 'image/jpeg'}) {
    return AiMessage._('user', [
      {'type': 'text', 'text': text},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,$base64Image'},
      },
    ]);
  }

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// AI 调用异常（带友好提示）
class AiException implements Exception {
  final String message;
  AiException(this.message);

  @override
  String toString() => message;

  static AiException fromDio(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    String detail = '';
    if (body is Map) {
      final err = body['error'];
      if (err is Map) detail = '${err['message'] ?? ''}';
    } else if (body is String) {
      detail = body.length > 300 ? body.substring(0, 300) : body;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return AiException('连接超时，请检查网络或稍后再试');
    }
    if (e.type == DioExceptionType.connectionError) {
      return AiException('无法连接到接口地址，请检查网络与 baseUrl');
    }
    switch (code) {
      case 401:
      case 403:
        return AiException('鉴权失败（$code）：请检查 API Key 是否正确$detail');
      case 402:
        return AiException('账户余额不足（402）$detail');
      case 404:
        return AiException('接口或模型不存在（404）：请检查 baseUrl 与模型名$detail');
      case 429:
        return AiException('请求过于频繁或额度受限（429），请稍后再试$detail');
      default:
        if (code != null && code >= 500) {
          return AiException('服务端错误（$code），请稍后再试$detail');
        }
        return AiException('请求失败${code != null ? '（$code）' : ''}$detail');
    }
  }
}

/// OpenAI 兼容客户端（覆盖 DeepSeek / 智谱 / OpenAI / 各类中转站）
class AiClient {
  AiClient(this._dio);

  final Dio _dio;

  Future<String> chat({
    required AiEndpoint endpoint,
    required String model,
    required List<AiMessage> messages,
    bool jsonMode = false,
    double temperature = 0.7,
    int? maxTokens,
    int timeoutSeconds = 120,
  }) async {
    final url = '${_trimSlash(endpoint.baseUrl)}/chat/completions';
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': temperature,
      'stream': false,
      'max_tokens': ?maxTokens,
    };
    if (jsonMode) body['response_format'] = {'type': 'json_object'};

    final options = Options(
      headers: {
        'Authorization': 'Bearer ${endpoint.apiKey}',
        'Content-Type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: Duration(seconds: timeoutSeconds),
    );

    try {
      final resp = await _dio.post<Map<String, dynamic>>(url, data: body, options: options);
      return _extractContent(resp.data);
    } on DioException catch (e) {
      // 部分服务不支持 response_format，仅对 400/422 且错误体明确提及
      // response_format/json 时降级重试一次；其他 400/422（图片过大、上下文
      // 超限等）重试只是重复计费。重试失败时优先抛出首次错误（A1）。
      final code = e.response?.statusCode;
      final detail = _errorBodyText(e);
      final looksLikeJsonModeIssue = detail.contains('response_format') ||
          detail.contains('json_object') ||
          detail.contains('json_schema') ||
          detail.toLowerCase().contains('json mode');
      if (jsonMode && (code == 400 || code == 422) && looksLikeJsonModeIssue) {
        body.remove('response_format');
        try {
          final resp = await _dio.post<Map<String, dynamic>>(url, data: body, options: options);
          return _extractContent(resp.data);
        } catch (_) {
          throw AiException.fromDio(e); // 保留首次错误，更能反映真实原因
        }
      }
      throw AiException.fromDio(e);
    }
  }

  String _errorBodyText(DioException e) {
    final body = e.response?.data;
    if (body is Map) {
      final err = body['error'];
      if (err is Map && err['message'] != null) return '${err['message']}';
      if (body['message'] != null) return '${body['message']}';
      return '$body';
    }
    if (body is String) return body;
    return '';
  }

  /// 测试连通性
  Future<String> ping(AiEndpoint endpoint, String model) async {
    return chat(
      endpoint: endpoint,
      model: model,
      messages: [AiMessage.userText('请只回复两个字符：OK')],
      maxTokens: 16,
      timeoutSeconds: 30,
    );
  }

  String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  String _extractContent(Map<String, dynamic>? data) {
    if (data == null) throw AiException('接口返回为空');
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map) {
        final content = msg['content'];
        if (content is String && content.isNotEmpty) return content;
        // 部分视觉模型返回分段结构
        if (content is List) {
          final buf = StringBuffer();
          for (final part in content) {
            if (part is Map && part['text'] != null) buf.write(part['text']);
          }
          if (buf.isNotEmpty) return buf.toString();
        }
        // 推理模型（如 deepseek-reasoner）正文可能放在 reasoning_content
        final reasoning = msg['reasoning_content'];
        if (reasoning is String && reasoning.isNotEmpty) return reasoning;
      }
    }
    final raw = data.toString();
    throw AiException('接口返回格式无法解析：${raw.length > 200 ? raw.substring(0, 200) : raw}');
  }
}
