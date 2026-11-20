class PlantTranslation {
  String? label;
  List<dynamic> names = [];
  List<dynamic> sourceUrls = [];
  String? wikipedia;
  String? description;
  String? flower;
  String? inflorescence;
  String? fruit;
  String? leaf;
  String? stem;
  String? habitat;
  String? toxicity;
  String? herbalism;
  String? trivia;

  PlantTranslation();

  PlantTranslation.fromJson(Map data) {
    label = data['label'];
    names = (data['names'] as List<dynamic>?) ?? [];
    sourceUrls = (data['sourceUrls'] as List<dynamic>?) ?? [];
    wikipedia = data['wikipedia'];
    description = data['description'];
    flower = data['flower'];
    inflorescence = data['inflorescence'];
    fruit = data['fruit'];
    leaf = data['leaf'];
    stem = data['stem'];
    habitat = data['habitat'];
    toxicity = data['toxicity'];
    herbalism = data['herbalism'];
    trivia = data['trivia'];
  }

  /// Fills empty body fields from [fallback]. Leaves [label] and [names] alone.
  void fillMissingFrom(PlantTranslation fallback) {
    description = _keepText(description, fallback.description);
    flower = _keepText(flower, fallback.flower);
    inflorescence = _keepText(inflorescence, fallback.inflorescence);
    fruit = _keepText(fruit, fallback.fruit);
    leaf = _keepText(leaf, fallback.leaf);
    stem = _keepText(stem, fallback.stem);
    habitat = _keepText(habitat, fallback.habitat);
    toxicity = _keepText(toxicity, fallback.toxicity);
    herbalism = _keepText(herbalism, fallback.herbalism);
    trivia = _keepText(trivia, fallback.trivia);
    wikipedia = _keepText(wikipedia, fallback.wikipedia);
    if (sourceUrls.isEmpty && fallback.sourceUrls.isNotEmpty) {
      sourceUrls = List<dynamic>.from(fallback.sourceUrls);
    }
  }

  bool isTranslated() {
    return _keepText(description, null) != null &&
        _keepText(flower, null) != null &&
        _keepText(inflorescence, null) != null &&
        _keepText(fruit, null) != null &&
        _keepText(leaf, null) != null &&
        _keepText(stem, null) != null &&
        _keepText(habitat, null) != null;
  }

  bool hasAllBodyFields() {
    return isTranslated() &&
        _keepText(toxicity, null) != null &&
        _keepText(herbalism, null) != null &&
        _keepText(trivia, null) != null;
  }
}

String? _keepText(String? current, String? fallback) {
  if (current != null && current.trim().isNotEmpty) {
    return current;
  }
  if (fallback != null && fallback.trim().isNotEmpty) {
    return fallback;
  }
  return null;
}