import '../models/display_settings.dart';
import 'signage_api.dart';

class DisplaySettingsService {
  DisplaySettingsService(this.api);
  final SignageApi api;
  Future<DisplaySettingsModel> load() async =>
      DisplaySettingsModel.fromJson(await api.displayRequest('settings'));
  Future<DisplaySettingsModel> apply({
    required String fitMode,
    int? rotation,
    String? output,
  }) async => DisplaySettingsModel.fromJson(
    await api.displayRequest(
      rotation == null ? 'fit-mode' : 'orientation',
      method: 'PUT',
      body: {
        'fit_mode': fitMode,
        'rotation': ?rotation,
        if (rotation != null) 'output': ?output,
      },
    ),
  );
  Future<DisplaySettingsModel> reset(String? output) async =>
      DisplaySettingsModel.fromJson(
        await api.displayRequest(
          'reset',
          method: 'POST',
          body: {'rotation': 0, 'output': ?output},
        ),
      );
}
