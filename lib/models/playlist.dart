class SavedPlaylist {
  const SavedPlaylist({
    required this.id,
    required this.name,
    required this.items,
    required this.imageDuration,
    required this.loop,
    required this.revision,
  });
  final String id;
  final String name;
  final List<String> items;
  final int imageDuration;
  final bool loop;
  final int revision;

  factory SavedPlaylist.fromJson(Map<String, dynamic> json) => SavedPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    items: (json['items'] as List<dynamic>).cast<String>(),
    imageDuration: json['image_duration'] as int,
    loop: json['loop'] as bool,
    revision: json['revision'] as int,
  );
}

class PlaylistCollection {
  const PlaylistCollection({required this.playlists, this.selectedId});
  final List<SavedPlaylist> playlists;
  final String? selectedId;

  factory PlaylistCollection.fromJson(Map<String, dynamic> json) =>
      PlaylistCollection(
        selectedId: json['selected_id'] as String?,
        playlists: (json['playlists'] as List<dynamic>)
            .map((item) => SavedPlaylist.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class PlaylistDraft {
  const PlaylistDraft({
    required this.name,
    required this.items,
    required this.imageDuration,
    required this.loop,
    this.revision = 0,
  });
  final String name;
  final List<String> items;
  final int imageDuration;
  final bool loop;
  final int revision;
  Map<String, Object> toJson() => {
    'name': name,
    'items': items,
    'image_duration': imageDuration,
    'loop': loop,
    'revision': revision,
  };
}
