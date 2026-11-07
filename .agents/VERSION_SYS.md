Inoov – Application Versioning Strategy
We use Semantic Versioning (MAJOR.MINOR.PATCH) with a monotonically increasing Android build number. A date may inform the build number, but must never make it lower than the latest Play upload.

Format:
version: MAJOR.MINOR.PATCH+BUILD_NUMBER


Example:
version: 1.1.4+711261135


Convention:
- MAJOR: Significant changes or breaking updates.
- MINOR: New features and improvements.
- PATCH: Bug fixes and minor corrections.
- BUILD_NUMBER: Android versionCode / Google Play build number.
Rules:
1. Each application maintains its own versioning sequence.
2. Before every Play upload, check the latest versionCode in Play Console and use a strictly higher number.
3. Never reuse a build number. A date-based number is optional and may only be used when it is higher than the latest uploaded versionCode; otherwise increment the latest code by at least one.
4. The public version changes according to the significance of the update.
5. Keep Android version codes below Google Play's maximum of 2,100,000,000.

Incident note:
- The Play Store build 1.1.03 used versionCode 711261134. The fixed release uses 1.1.4+711261135 so Google Play accepts it as an upgrade.
- Do not use a short date code such as 26110703 for this app unless it exceeds the latest Play Console versionCode.

Objective: Maintain simple, consistent, traceable, and professional version management across all Inoov applications.