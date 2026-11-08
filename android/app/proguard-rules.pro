# ML Kit text recognition (google_mlkit_text_recognition 1.0.1): the plugin
# references the Chinese / Devanagari / Japanese / Korean recognizer option
# classes, which it declares compileOnly (not packaged — the app only uses
# Latin). R8 fails the release build on the missing classes unless they
# are silenced here; this is the remedy R8 itself suggests (missing_rules.txt).
-dontwarn com.google.mlkit.vision.text.**
