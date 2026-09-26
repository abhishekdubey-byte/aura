/// Wording chosen by the user, never inferred from a face, outfit or body.
/// This preference has no effect on points or quality requirements.
enum SlangStyle {
  neutral('Neutral'),
  masculine('Masculine'),
  feminine('Feminine');

  const SlangStyle(this.label);
  final String label;
  static const preferenceKey = 'aura_slang_style';

  static SlangStyle fromStored(String? value) =>
      values.firstWhere((style) => style.name == value, orElse: () => neutral);

  String format(String neutralText) {
    final variants = _variants[neutralText];
    if (variants == null || this == neutral) return neutralText;
    return this == masculine ? variants.$1 : variants.$2;
  }

  static const _variants = <String, (String, String)>{
    'Ice Cool 🧊': ('Ice King 🧊', 'Ice Queen 🧊'),
    'Symmetry Icon 📐': ('Symmetry King 📐', 'Symmetry Queen 📐'),
    'Athletic Energy ⚡': ('Athletic King ⚡', 'Athletic Queen ⚡'),
    'Main-character energy 💫': ('Leading Man 💫', 'Leading Lady 💫'),
    'Style Icon ✨': ('Style King ✨', 'Style Queen ✨'),
  };
}
