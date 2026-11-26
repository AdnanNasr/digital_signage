enum PlayerCommand {
  start('start'),
  pause('pause'),
  resume('resume'),
  stop('stop'),
  next('next'),
  previous('previous'),
  restart('restart');

  const PlayerCommand(this.path);
  final String path;
}

class PlayerStatus {
  const PlayerStatus({
    required this.state,
    required this.reachable,
    required this.videoCount,
    this.currentFile,
    this.imageCount = 0,
    this.currentPlaylistName,
    this.currentPlaylistId,
  });

  final String state;
  final bool reachable;
  final int videoCount;
  final int imageCount;
  final String? currentPlaylistName;
  final String? currentPlaylistId;
  int get mediaCount => videoCount + imageCount;
  final String? currentFile;

  bool get isActive => state == 'playing' || state == 'paused';

  String get label => switch (state) {
    'playing' => 'Wird wiedergegeben',
    'paused' => 'Pausiert',
    'stopped' => 'Gestoppt',
    'unreachable' => 'Nicht erreichbar',
    _ => 'Fehler',
  };

  factory PlayerStatus.fromJson(Map<String, dynamic> json) => PlayerStatus(
    state: json['state'] as String,
    reachable: json['reachable'] as bool,
    videoCount: json['video_count'] as int,
    imageCount: json['image_count'] as int? ?? 0,
    currentPlaylistName: json['current_playlist_name'] as String?,
    currentPlaylistId: json['current_playlist_id'] as String?,
    currentFile: json['current_file'] as String?,
  );
}
