class DisplayOutput {
  const DisplayOutput(
    this.name,
    this.rotation,
    this.width,
    this.height,
    this.rotations,
  );
  final String name;
  final int? rotation;
  final int width;
  final int height;
  final List<int> rotations;
  factory DisplayOutput.fromJson(Map<String, dynamic> json) {
    final resolution = json['resolution'] as Map<String, dynamic>;
    return DisplayOutput(
      json['name'] as String,
      json['rotation'] as int?,
      resolution['width'] as int,
      resolution['height'] as int,
      (json['rotations'] as List).cast<int>(),
    );
  }
}

class DisplaySettingsModel {
  const DisplaySettingsModel({
    required this.output,
    required this.rotation,
    required this.fitMode,
    required this.session,
    required this.outputs,
    required this.available,
    this.error,
    this.width,
    this.height,
  });
  final String? output;
  final int? rotation;
  final String fitMode;
  final String session;
  final List<DisplayOutput> outputs;
  final bool available;
  final String? error;
  final int? width;
  final int? height;
  factory DisplaySettingsModel.fromJson(Map<String, dynamic> json) {
    final resolution = json['resolution'] as Map<String, dynamic>?;
    return DisplaySettingsModel(
      output: json['output'] as String?,
      rotation: json['rotation'] as int?,
      fitMode: json['fit_mode'] as String,
      session: json['session'] as String,
      outputs: (json['outputs'] as List)
          .map((v) => DisplayOutput.fromJson(v as Map<String, dynamic>))
          .toList(),
      available: json['available'] as bool,
      error: json['error'] as String?,
      width: resolution?['width'] as int?,
      height: resolution?['height'] as int?,
    );
  }
}
