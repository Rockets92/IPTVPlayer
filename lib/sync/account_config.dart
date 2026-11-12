/// Progetto Supabase dell'account. La chiave è quella pubblica
/// ("publishable"): può stare nell'app, i dati sono protetti dalle regole di
/// accesso del database. Si può sostituire in compilazione con
/// `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_KEY=…`.
abstract final class AccountConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yrgdckgyiodyeqfarsye.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_ZkX94zQkvxoBO4f_BIQrcQ_bRlx6yGI',
  );

  static bool get enabled => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Telecomando unico sul telefono (GitHub Pages del repository).
  static const remoteWebUrl = String.fromEnvironment(
    'REMOTE_WEB_URL',
    defaultValue: 'https://rockets92.github.io/IPTVPlayer/',
  );
}
