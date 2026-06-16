/// Source of a master-data load — distinguishes a real network fetch from a
/// cache hit or an empty result.
enum MasterDataSource {
  /// Data was fetched from the network and persisted locally.
  network,

  /// Data was served from the local SQLite cache (offline or cache-hit).
  cache,

  /// No data available (empty response or empty CT list).
  empty,
}

/// Result returned by [GasoductosService.reload] and [PksService.reload].
///
/// Carries both the [source] (network/cache/empty) and the number of
/// items loaded, so the controller can decide whether to advance the
/// "last download" timestamp (only for [MasterDataSource.network]) and
/// whether to show a "served from cache" hint.
class MasterDataLoadResult {
  final MasterDataSource source;
  final int itemCount;

  const MasterDataLoadResult(this.source, this.itemCount);

  @override
  String toString() =>
      'MasterDataLoadResult(source: $source, itemCount: $itemCount)';
}
