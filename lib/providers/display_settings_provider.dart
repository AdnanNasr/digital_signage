import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/display_settings.dart';
import '../services/display_settings_service.dart';
import '../services/signage_api.dart';
import 'dashboard_provider.dart';

final displaySettingsProvider =
    NotifierProvider<DisplaySettingsController, DisplaySettingsState>(
      DisplaySettingsController.new,
    );

class DisplaySettingsState {
  const DisplaySettingsState({
    this.settings,
    this.busy = false,
    this.error,
    this.message,
  });
  final DisplaySettingsModel? settings;
  final bool busy;
  final String? error;
  final String? message;
}

class DisplaySettingsController extends Notifier<DisplaySettingsState> {
  int _generation = 0;
  @override
  DisplaySettingsState build() {
    ref.watch(dashboardProvider.select((s) => s.hasSession));
    _generation++;
    return const DisplaySettingsState();
  }

  Future<void> load() => _run((service) => service.load());
  Future<void> apply(String fitMode, int? rotation, String? output) => _run(
    (service) =>
        service.apply(fitMode: fitMode, rotation: rotation, output: output),
    rotation == null ? 'Die Einstellungen wurden erfolgreich gespeichert.' : 'Die Bildschirmausrichtung wurde erfolgreich geändert. Die Einstellungen wurden erfolgreich gespeichert.',
  );
  Future<void> reset(String? output) => _run(
    (service) => service.reset(output),
    'Die Einstellungen wurden erfolgreich gespeichert.',
  );
  Future<void> _run(
    Future<DisplaySettingsModel> Function(DisplaySettingsService) action, [
    String? message,
  ]) async {
    final api = ref.read(dashboardProvider.notifier).api;
    if (api == null || state.busy) return;
    final generation = _generation;
    state = DisplaySettingsState(settings: state.settings, busy: true);
    try {
      final settings = await action(DisplaySettingsService(api));
      if (!ref.mounted || generation != _generation) return;
      state = DisplaySettingsState(settings: settings, message: message);
    } on ApiException catch (error) {
      if (!ref.mounted || generation != _generation) return;
      if (error.statusCode == 401) {
        ref.read(dashboardProvider.notifier).expireSession();
        return;
      }
      // Reload actual state after a failed application or rollback.
      DisplaySettingsModel? actual;
      try {
        actual = await DisplaySettingsService(api).load();
      } on ApiException {
        /* Retry explicitly. */
      }
      if (!ref.mounted || generation != _generation) return;
      state = DisplaySettingsState(settings: actual, error: error.message);
    }
  }
}
