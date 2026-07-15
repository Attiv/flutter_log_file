/// Memory and presentation limits used by the bundled log viewer.
final class VLogViewerConfig {
  const VLogViewerConfig({
    this.chunkSizeBytes = 128 * 1024,
    this.memoryBudgetBytes = 4 * 1024 * 1024,
    this.initialTailLines = 500,
    this.maximumLineBytes = 1024 * 1024,
    this.maximumSearchResults = 5000,
    this.wrapLines = true,
  })  : assert(chunkSizeBytes > 0),
        assert(memoryBudgetBytes > 0),
        assert(initialTailLines > 0),
        assert(maximumLineBytes > 0),
        assert(maximumSearchResults > 0);

  final int chunkSizeBytes;
  final int memoryBudgetBytes;
  final int initialTailLines;
  final int maximumLineBytes;
  final int maximumSearchResults;
  final bool wrapLines;
}
