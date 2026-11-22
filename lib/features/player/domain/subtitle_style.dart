/// Subtitle appearance, applied to mpv live and persisted in PlayerSettings.
class SubtitleStyle {
  const SubtitleStyle({
    this.scale = 1.0,
    this.pos = 100,
    this.yellow = false,
    this.box = true,
  });

  /// Size presets (sub-scale).
  static const scales = [0.8, 1.0, 1.2, 1.5];

  /// sub-scale: 0.8 / 1.0 / 1.2 / 1.5.
  final double scale;

  /// sub-pos: 0 (top) .. 100 (bottom).
  final int pos;
  final bool yellow;

  /// Opaque-ish background box behind the text.
  final bool box;

  SubtitleStyle copyWith({double? scale, int? pos, bool? yellow, bool? box}) =>
      SubtitleStyle(
        scale: scale ?? this.scale,
        pos: pos ?? this.pos,
        yellow: yellow ?? this.yellow,
        box: box ?? this.box,
      );

  /// mpv properties for this style (`#AARRGGBB` colours).
  Map<String, String> mpvProps() => {
    'sub-scale': scale.toString(),
    'sub-pos': pos.toString(),
    'sub-color': yellow ? '#FFFFFF00' : '#FFFFFFFF',
    'sub-border-style': box ? 'background-box' : 'outline-and-shadow',
    'sub-back-color': '#AA000000',
  };

  Map<String, Object?> toJson() => {
    'scale': scale,
    'pos': pos,
    'yellow': yellow,
    'box': box,
  };

  factory SubtitleStyle.fromJson(Object? j) {
    if (j is! Map) return const SubtitleStyle();
    final s = j['scale'];
    final p = j['pos'];
    return SubtitleStyle(
      scale: s is num && scales.contains(s.toDouble()) ? s.toDouble() : 1.0,
      pos: p is int ? p.clamp(0, 100) : 100,
      yellow: j['yellow'] == true,
      box: j['box'] is bool ? j['box'] as bool : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SubtitleStyle &&
      other.scale == scale &&
      other.pos == pos &&
      other.yellow == yellow &&
      other.box == box;
  @override
  int get hashCode => Object.hash(scale, pos, yellow, box);
}
