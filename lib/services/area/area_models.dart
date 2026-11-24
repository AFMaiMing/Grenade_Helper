class AutoTagSummary {
  final int processedGrenades;
  final int matchedGrenades;
  final int addedLinks;
  final int removedLinks;
  final Map<String, int> areaMatches;

  const AutoTagSummary({
    required this.processedGrenades,
    required this.matchedGrenades,
    required this.addedLinks,
    required this.removedLinks,
    required this.areaMatches,
  });
}

class AreaTagSyncSummary {
  final int processedGrenades;
  final int matchedGrenades;
  final int addedLinks;
  final int removedLinks;

  const AreaTagSyncSummary({
    required this.processedGrenades,
    required this.matchedGrenades,
    required this.addedLinks,
    required this.removedLinks,
  });
}
