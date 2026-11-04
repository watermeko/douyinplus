Map<String, dynamic> asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return const <String, dynamic>{};
}

List<dynamic> asList(dynamic value) =>
    value is List ? value : const <dynamic>[];

String asString(dynamic value) => value?.toString() ?? '';

int asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(asString(value)) ?? 0;
}

bool asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = asString(value).toLowerCase();
  return text == 'true' || text == '1';
}

List<String> stringList(dynamic value) {
  return [
    for (final item in asList(value))
      if (asString(item).trim().isNotEmpty) asString(item).trim(),
  ];
}

List<String> urlListOf(Map<String, dynamic> object) =>
    stringList(object['url_list']);

String? firstUrlOf(Map<String, dynamic> object) {
  final urls = urlListOf(object);
  return urls.isEmpty ? null : urls.first;
}

List<String> dedupeUrls(Iterable<String> urls) {
  final seen = <String>{};
  final result = <String>[];
  for (final url in urls) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) result.add(trimmed);
  }
  return result;
}
