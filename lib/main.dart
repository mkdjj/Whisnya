import 'dart:async';

import 'package:flutter/material.dart';

import 'models/app_settings.dart';
import 'screens/home_screen.dart';
import 'services/ai_service.dart';
import 'services/local_storage_service.dart';
import 'services/qq/qq_integration_runtime.dart';
import 'utils/app_i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = LocalStorageService();
  final aiService = AiService();
  await storage.ensureReady();
  final qqRuntime = QqIntegrationRuntime(
    storage: storage,
    aiGateway: aiService,
  );
  await qqRuntime.initialize();
  runApp(
    WhisnyaApp(storage: storage, aiService: aiService, qqRuntime: qqRuntime),
  );
}

class WhisnyaApp extends StatefulWidget {
  const WhisnyaApp({
    required this.storage,
    required this.aiService,
    this.qqRuntime,
    super.key,
  });

  final LocalStorageService storage;
  final AiService aiService;
  final QqIntegrationRuntime? qqRuntime;

  @override
  State<WhisnyaApp> createState() => _WhisnyaAppState();
}

class _WhisnyaAppState extends State<WhisnyaApp> {
  AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    late final AppSettings settings;
    try {
      settings = await widget.storage.loadSettings();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Whisnya',
      locale: appLocaleFromCode(_settings.languageCode),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      themeMode: _settings.themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(_settings.fontScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(
        storage: widget.storage,
        aiService: widget.aiService,
        qqRuntime: widget.qqRuntime,
        settings: _settings,
        onSettingsChanged: _loadSettings,
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2B6CB0),
        brightness: brightness,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      useMaterial3: true,
    );
    final color = _settings.interfaceTextColor == null
        ? null
        : Color(_settings.interfaceTextColor!);
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: color, displayColor: color),
    );
  }
}
