import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/player_status.dart';
import '../services/signage_api.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final dashboardProvider = NotifierProvider<DashboardController, DashboardState>(
  DashboardController.new,
);

class DashboardState {
  const DashboardState({
    this.status,
    this.hasSession = false,
    this.connected = false,
    this.busy = false,
    this.error,
  });

  final PlayerStatus? status;
  final bool hasSession;
  final bool connected;
  final bool busy;
  final String? error;
}

class DashboardController extends Notifier<DashboardState> {
  SignageApi? _api;
  SignageApi? get api => _api;
  Timer? _timer;
  int _generation = 0;

  @override
  DashboardState build() {
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
    });
    return const DashboardState();
  }

  Future<void> connect(Uri url, String token) async {
    if (state.busy) return;
    _api = SignageApi(url, token, ref.read(httpClientProvider));
    await _update(initial: true);
    if (ref.mounted && state.hasSession) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    }
  }

  Future<void> refresh() => _update();
  Future<void> command(PlayerCommand command) => _update(command: command);

  Future<void> _update({PlayerCommand? command, bool initial = false}) async {
    final api = _api;
    if (api == null || state.busy) return;
    final generation = _generation;
    final previous = state;
    state = DashboardState(
      status: previous.status,
      hasSession: previous.hasSession,
      connected: previous.connected,
      busy: true,
    );
    try {
      final status = command == null
          ? await api.status()
          : await api.command(command);
      if (!ref.mounted || generation != _generation) return;
      state = DashboardState(status: status, hasSession: true, connected: true);
    } on ApiException catch (error) {
      PlayerStatus? status;
      if (command != null &&
          error.statusCode != null &&
          error.statusCode != 401) {
        try {
          status = await api.status();
        } on ApiException {
          // Polling will retry; never present old playback data as current.
        }
      }
      if (!ref.mounted || generation != _generation) return;
      final hasSession = !initial && error.statusCode != 401;
      state = DashboardState(
        status: status,
        hasSession: hasSession,
        connected: status != null,
        error: error.message,
      );
      if (!hasSession) {
        _timer?.cancel();
        _api = null;
      }
    }
  }

  void disconnect() {
    _generation++;
    _timer?.cancel();
    _api = null;
    state = const DashboardState();
  }

  void expireSession() {
    disconnect();
    state = const DashboardState(
      error: 'Das Passwort ist ungültig. Bitte erneut anmelden.',
    );
  }
}
