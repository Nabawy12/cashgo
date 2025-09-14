abstract class DBHelper {
  static DBHelper get instance =>
      throw UnsupportedError('DBHelper not implemented for this platform.');

  Future<void> ensureInitialized();
}
