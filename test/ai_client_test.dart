import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitmate/ai/ai_client.dart';

/// 捕获请求并按脚本返回响应的假适配器（无需真实网络）
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<Map<String, dynamic>> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data;
    if (body is Map) {
      requests.add(Map<String, dynamic>.from(body));
    }
    return handler(options);
  }
}

ResponseBody _json(Object? payload, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

AiEndpoint get _endpoint => const AiEndpoint(name: 't', baseUrl: 'https://api.test', apiKey: 'sk-x');

Future<AiClient> _clientWith(ResponseBody Function(RequestOptions) handler) async {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter(handler);
  return AiClient(dio);
}

Map<String, dynamic> _lastBody(_FakeAdapter adapter) => adapter.requests.last;

void main() {
  test('正常返回：解析 choices[0].message.content', () async {
    final client = await _clientWith((o) => _json({
          'choices': [
            {'message': {'content': '你好'}}
          ],
        }));
    final out = await client.chat(
      endpoint: _endpoint,
      model: 'm',
      messages: [AiMessage.userText('hi')],
    );
    expect(out, '你好');
  });

  test('jsonMode 首次 400 且错误提及 response_format → 自动降级重试成功', () async {
    final adapter = _FakeAdapter((o) {
      final hasRf = (o.data as Map)['response_format'] != null;
      if (hasRf) {
        return _json({
          'error': {'message': 'response_format is not supported'}
        }, 400);
      }
      return _json({
        'choices': [
          {'message': {'content': '{"items":[]}'}}
        ],
      });
    });
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    final client = AiClient(dio);

    final out = await client.chat(
      endpoint: _endpoint,
      model: 'm',
      messages: [AiMessage.userText('hi')],
      jsonMode: true,
    );
    expect(out, '{"items":[]}');
    expect(adapter.requests, hasLength(2));
    expect(_lastBody(adapter).containsKey('response_format'), isFalse,
        reason: '重试请求必须已去掉 response_format');
  });

  test('jsonMode 首次 400 但与 response_format 无关 → 不重试，保留首次错误', () async {
    var calls = 0;
    final adapter = _FakeAdapter((o) {
      calls++;
      return _json({
        'error': {'message': 'image too large'}
      }, 400);
    });
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    final client = AiClient(dio);

    await expectLater(
      client.chat(
        endpoint: _endpoint,
        model: 'm',
        messages: [AiMessage.userText('hi')],
        jsonMode: true,
      ),
      throwsA(isA<AiException>().having((e) => e.message, 'msg', contains('image too large'))),
    );
    expect(calls, 1, reason: '与 response_format 无关的 400 不应重试');
  });

  test('401 不重试，错误信息包含鉴权提示', () async {
    var calls = 0;
    final adapter = _FakeAdapter((o) {
      calls++;
      return _json({
        'error': {'message': 'invalid key'}
      }, 401);
    });
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    final client = AiClient(dio);

    await expectLater(
      client.chat(
        endpoint: _endpoint,
        model: 'm',
        messages: [AiMessage.userText('hi')],
        jsonMode: true,
      ),
      throwsA(isA<AiException>().having((e) => e.message, 'msg', contains('鉴权'))),
    );
    expect(calls, 1);
  });

  test('推理模型：content 为空时回退 reasoning_content', () async {
    final client = await _clientWith((o) => _json({
          'choices': [
            {
              'message': {'content': '', 'reasoning_content': '计划正文'}
            }
          ],
        }));
    final out = await client.chat(
      endpoint: _endpoint,
      model: 'reasoner',
      messages: [AiMessage.userText('hi')],
    );
    expect(out, '计划正文');
  });

  test('分段 content（部分视觉模型）拼接 text', () async {
    final client = await _clientWith((o) => _json({
          'choices': [
            {
              'message': {
                'content': [
                  {'type': 'text', 'text': 'A'},
                  {'type': 'text', 'text': 'B'},
                ]
              }
            }
          ],
        }));
    final out = await client.chat(
      endpoint: _endpoint,
      model: 'v',
      messages: [AiMessage.userText('hi')],
    );
    expect(out, 'AB');
  });

  test('畸形 200（choices 非列表）→ 抛 AiException 而非裸异常', () async {
    final client = await _clientWith((o) => _json({'choices': 'oops'}));
    await expectLater(
      client.chat(endpoint: _endpoint, model: 'm', messages: [AiMessage.userText('hi')]),
      throwsA(isA<AiException>()),
    );
  });

  test('图片消息按 OpenAI 兼容格式编码 base64 image_url', () async {
    final adapter = _FakeAdapter((o) => _json({
          'choices': [
            {'message': {'content': 'ok'}}
          ],
        }));
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    final client = AiClient(dio);

    await client.chat(
      endpoint: _endpoint,
      model: 'vision',
      messages: [AiMessage.userWithImage('看图', 'QUJD', mime: 'image/png')],
    );
    final body = _lastBody(adapter);
    final parts = (body['messages'].first['content'] as List);
    expect(parts[1]['type'], 'image_url');
    expect(parts[1]['image_url']['url'], 'data:image/png;base64,QUJD');
  });

  test('ping 走同一链路', () async {
    final client = await _clientWith((o) => _json({
          'choices': [
            {'message': {'content': 'OK'}}
          ],
        }));
    final out = await client.ping(_endpoint, 'm');
    expect(out, 'OK');
  });
}
