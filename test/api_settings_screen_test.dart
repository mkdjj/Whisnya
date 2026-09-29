import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/models/api_config.dart';
import 'package:whisnya/screens/api_settings_screen.dart';
import 'package:whisnya/services/ai_service.dart';
import 'package:whisnya/services/local_storage_service.dart';

void main() {
  testWidgets('default API card fits narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _MemoryStorage();
    storage.saved = ApiConfig(
      defaultEndpointId: 'one',
      endpoints: [
        AiEndpointConfig.fromJson({
          'id': 'one',
          'name': '很长的自定义 API 配置名称',
          'model': 'a-long-model-name',
          'baseUrl': 'https://example.com/v1',
        }),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ApiSettingsScreen(storage: storage, aiService: _ModelAiService()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('很长的自定义 API 配置名称'), findsOneWidget);
  });
  testWidgets('loads models after URL and key and saves the automatic choice', (
    tester,
  ) async {
    final storage = await _openDialog(tester, _ModelAiService());
    await _enterCredentials(tester);

    expect(find.textContaining('alpha-chat'), findsOneWidget);

    await _save(tester);

    expect(storage.saved.endpoints.single.model, 'alpha-chat');
  });

  testWidgets('offers every returned model in the dropdown', (tester) async {
    final storage = await _openDialog(tester, _ModelAiService());
    await _enterCredentials(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('general-model').last);
    await tester.pumpAndSettle();
    await _save(tester);

    expect(storage.saved.endpoints.single.model, 'general-model');
  });

  testWidgets('keeps manual model input when model discovery fails', (
    tester,
  ) async {
    final storage = await _openDialog(tester, _FailingAiService());
    await _enterCredentials(tester);

    expect(find.textContaining('无法获取模型'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'manual-model');
    await _save(tester);

    expect(storage.saved.endpoints.single.model, 'manual-model');
  });

  testWidgets('shows storage errors instead of leaking them', (tester) async {
    final storage = await _openDialog(
      tester,
      _ModelAiService(),
      failSave: true,
    );
    await _enterCredentials(tester);
    await _save(tester);

    expect(tester.takeException(), isNull);
    expect(storage.saved.endpoints, isEmpty);
    expect(find.textContaining('save failed'), findsOneWidget);
  });
}

Future<_MemoryStorage> _openDialog(
  WidgetTester tester,
  AiService aiService, {
  bool failSave = false,
}) async {
  final storage = _MemoryStorage(failSave: failSave);
  await tester.pumpWidget(
    MaterialApp(
      home: ApiSettingsScreen(storage: storage, aiService: aiService),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add).first);
  await tester.pumpAndSettle();
  return storage;
}

Future<void> _enterCredentials(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(1), 'secret');
  await tester.enterText(fields.at(2), 'https://example.com/v1');
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    ),
  );
  await tester.pumpAndSettle();
}

final class _MemoryStorage extends LocalStorageService {
  _MemoryStorage({this.failSave = false});

  final bool failSave;
  ApiConfig saved = ApiConfig();

  @override
  Future<ApiConfig> loadApiConfig() async => saved;

  @override
  Future<void> saveApiConfig(ApiConfig config) async {
    if (failSave) throw StateError('save failed');
    saved = config;
  }
}

final class _ModelAiService extends AiService {
  @override
  Future<List<String>> listModels({
    required String apiKey,
    required String baseUrl,
  }) async => ['text-embedding-3-small', 'general-model', 'alpha-chat'];
}

final class _FailingAiService extends AiService {
  @override
  Future<List<String>> listModels({
    required String apiKey,
    required String baseUrl,
  }) {
    throw AiException('无法获取模型');
  }
}
