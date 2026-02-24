# Voice Mode (Whisper + TTS)

Voice mode is available in:

- Chat composer
- Quick-action reply bubble

## Input (Speech to Text)

- One-tap mic flow
- Uses OpenAI realtime transcription first (server-side VAD turn detection)
- Auto-stop on detected end of speech
- Auto-transcribe and auto-send
- Fallback path uses local recording + transcription API

## Output (Text to Speech)

- Uses OpenAI TTS model `gpt-4o-mini-tts`
- Voice mode toggle enables auto-speaking agent replies

## Requirements

- OpenAI key in `Settings -> API Keys`
- Microphone permission enabled in macOS
