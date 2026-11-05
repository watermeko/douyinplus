/// Interactions (like / collect) perform writes on the user's real Douyin
/// account. They are enabled by default after the low-frequency write path was
/// validated end to end (v0.2.1). Disable them for a build with:
///
/// ```bash
/// flutter build apk --dart-define=DOUYINPLUS_ENABLE_INTERACTIONS=false
/// ```
const bool kEnableInteractions = bool.fromEnvironment(
  'DOUYINPLUS_ENABLE_INTERACTIONS',
  defaultValue: true,
);
