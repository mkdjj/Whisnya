import '../../models/qq_integration_settings.dart';

bool qqDeliveryPermitted({
  required bool running,
  required bool paused,
  required int currentGeneration,
  required int resultGeneration,
  required QqIntegrationSettings settings,
  required QqIntegrationMode mode,
}) =>
    running &&
    !paused &&
    currentGeneration == resultGeneration &&
    settings.enabled &&
    settings.mode == mode;
