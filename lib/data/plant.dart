class Plant{
  final String key;
  int id = 0;
  String? ipniId;
  String name = "";
  String? author;
  Map<dynamic, dynamic> apgIV = {};
  int floweringFrom = 1;
  int floweringTo = 12;
  int heightFrom = 0;
  int heightTo = 0;
  int toxicityClass = 0;
  String? illustrationUrl;
  List<dynamic> photoUrls = [];
  List<dynamic> videoUrls = [];
  List<dynamic> sourceUrls = [];
  List<String> inflorescenceType = [];
  Map<dynamic, dynamic> wikiLinks = {};

  Plant.fromJson(this.key, Map data) {
    id = _intOr(data['id'], 0);
    name = data['name']?.toString() ?? '';
    author = data['author']?.toString();
    final rawApg = data['APGIV'];
    apgIV = rawApg is Map ? Map<dynamic, dynamic>.from(rawApg) : {};
    ipniId = data['ipniId']?.toString();
    floweringFrom = _intOr(data['floweringFrom'], 1);
    floweringTo = _intOr(data['floweringTo'], 0);
    heightFrom = _intOr(data['heightFrom'], 0);
    heightTo = _intOr(data['heightTo'], 0);
    toxicityClass = _intOr(data['toxicityClass'], 0);
    illustrationUrl = data['illustrationUrl']?.toString();
    photoUrls = _dynamicList(data['photoUrls']);
    videoUrls = _dynamicList(data['videoUrls']);
    sourceUrls = _dynamicList(data['sourceUrls']);
    inflorescenceType = _stringList(data['inflorescenceType']);
    final rawWiki = data['wikilinks'];
    wikiLinks = rawWiki is Map ? Map<dynamic, dynamic>.from(rawWiki) : {};
  }
}

int _intOr(dynamic raw, int fallback) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

List<dynamic> _dynamicList(dynamic raw) {
  if (raw is List) return List<dynamic>.from(raw);
  if (raw is Map) {
    final entries = raw.entries.toList()
      ..sort((a, b) => (int.tryParse(a.key.toString()) ?? 0)
          .compareTo(int.tryParse(b.key.toString()) ?? 0));
    return [for (final entry in entries) entry.value];
  }
  return [];
}

List<String> _stringList(dynamic raw) {
  if (raw is List) {
    return raw.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
  }
  if (raw is Map) {
    final keys = raw.keys.toList()
      ..sort((a, b) => (int.tryParse(a.toString()) ?? 0).compareTo(int.tryParse(b.toString()) ?? 0));
    return keys
        .map((key) => raw[key].toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return [];
}