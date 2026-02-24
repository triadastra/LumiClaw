# Troubleshooting

## Guided permissions crashes

Check `Info.plist` has required privacy keys:

- `NSMicrophoneUsageDescription`
- `NSCameraUsageDescription`
- `NSScreenCaptureUsageDescription`
- `NSAccessibilityUsageDescription`

## Permissions keep resetting

Likely due to app reinstall/signature changes. Keep bundle ID/signing stable.

## Voice input does not send

- Verify OpenAI API key exists
- Verify microphone permission
- Check network access

## Overlay not visible across apps

Ensure you are running the newest installed app build from `/Applications/LumiAgent.app`.
