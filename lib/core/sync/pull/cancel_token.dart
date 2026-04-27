/// Cooperative cancellation flag for long-running pull operations.
///
/// The caller (UI) holds a reference and calls [cancel]. The pull pipeline
/// checks [isCancelled] between phases and stops. Records already upserted
/// before cancellation are kept; the rest are left for a future pull.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}
