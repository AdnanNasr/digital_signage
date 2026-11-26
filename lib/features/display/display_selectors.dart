import 'package:flutter/material.dart';

const orientationLabels = {
  0: 'Querformat',
  90: 'Hochformat – 90°',
  180: 'Querformat – 180°',
  270: 'Hochformat – 270°',
};
const fitLabels = {
  'contain': 'Einpassen',
  'cover': 'Bildschirm ausfüllen',
  'stretch': 'Strecken',
};

class DisplayOrientationSelector extends StatelessWidget {
  const DisplayOrientationSelector({
    super.key,
    required this.value,
    required this.rotations,
    required this.onChanged,
  });
  final int? value;
  final List<int> rotations;
  final ValueChanged<int?>? onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    key: ValueKey('$value:$rotations'),
    initialValue: rotations.contains(value) ? value : null,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Bildschirmausrichtung'),
    items: [
      for (final angle in rotations)
        DropdownMenuItem(value: angle, child: Text(orientationLabels[angle]!)),
    ],
    onChanged: onChanged,
  );
}

class DisplayFitModeSelector extends StatelessWidget {
  const DisplayFitModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String?>? onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey(value),
    initialValue: fitLabels.containsKey(value) ? value : null,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Bildschirmdarstellung'),
    items: [
      for (final item in fitLabels.entries)
        DropdownMenuItem(value: item.key, child: Text(item.value)),
    ],
    onChanged: onChanged,
  );
}

class DisplayOrientationPreview extends StatelessWidget {
  const DisplayOrientationPreview({
    super.key,
    required this.rotation,
    required this.fitMode,
    required this.aspectRatio,
  });
  final int rotation;
  final String fitMode;
  final double aspectRatio;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('Vorschau', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RotatedBox(
            quarterTurns: rotation ~/ 90,
            child: const Icon(Icons.arrow_upward_rounded),
          ),
          const SizedBox(width: 8),
          Text('$rotation°'),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 220,
        child: Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF19294E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRect(
                child: ColoredBox(
                  color: Colors.black,
                  child: FittedBox(
                    fit: switch (fitMode) {
                      'cover' => BoxFit.cover,
                      'stretch' => BoxFit.fill,
                      _ => BoxFit.contain,
                    },
                    child: SizedBox(
                      width: 160,
                      height: 90,
                      child: ColoredBox(
                        color: const Color(0xFF405BC2),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Positioned(
                              left: 8,
                              top: 8,
                              child: Icon(
                                Icons.wb_sunny_rounded,
                                size: 20,
                                color: Color(0xFFF5CD45),
                              ),
                            ),
                            const Icon(
                              Icons.landscape_rounded,
                              size: 72,
                              color: Colors.white,
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Text(
                                '$rotation°',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Schematische Vorschau mit einem Beispiel im Format 16:9.',
        textAlign: TextAlign.center,
      ),
    ],
  );
}
