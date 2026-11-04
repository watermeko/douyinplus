/// Compile-time feature flags.
///
/// Interactions (like / collect) perform writes on the user's real Douyin
/// account. They stay off unless explicitly enabled at build time:
///
/// ```bash
/// flutter run --dart-define=DOUYINPLUS_ENABLE_INTERACTIONS=true
/// ```
///
/// Keep the default off for GitHub Release builds until the write path has
/// been validated on a disposable account without triggering risk control.
const bool kEnableInteractions = bool.fromEnvironment(
  'DOUYINPLUS_ENABLE_INTERACTIONS',
);
