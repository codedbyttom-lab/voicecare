# VoiceCare — Technical Manual

Version: 1.0

This technical manual describes the VoiceCare Flutter app architecture, key files and classes, voice and audio orchestration, Firebase data shapes, platform channels, build/run instructions, debugging tips, and extension points. It is intended for engineers who will maintain or extend the app.

---

## 1. Project Overview

VoiceCare is a Flutter application (multi-platform) that uses GetX for state management & navigation, integrates speech-to-text (STT) and text-to-speech (TTS) for a voice-first UX, and uses Firebase Authentication and Cloud Firestore for persistence (users, appointments, timeslots). The app contains both regular-user and admin flows.

Core runtime responsibilities:

- Orchestrate voice flows (onboarding/registration, login assist, appointment booking and cancellation, profile viewing)
- Play a short beep/cue before listening to avoid capturing TTS
- Persist users and appointments in Firestore
- Provide both voice-first and manual (touch & type) fallbacks

## 2. High-level Architecture

- UI layer: Flutter widgets in `lib/` (pages under `lib/homepage`, `lib/appointment`, `lib/registration`, `lib/admin`).
- Controllers (GetX): located under `lib/controllers/` (e.g., `sign_up_controller.dart`, `appointment_controller.dart`, `auth_controller.dart`). They own orchestration and business rules.
- Speech layer: `SpeechService` for general speech functionality (`lib/mic_widget/service_speech.dart`) and `AppointmentSpeechService` for appointment-specific speech logic (`lib/appointment/app_widget/appointment_service_speech.dart`).
- Firebase wrapper/services: `lib/Firebase/` contains `Auth_service.dart`, controllers like `auth_controller.dart` use them.
- Native integration: platform MethodChannel for short beep playback (channel name used in code: `voicecare/audio`).

## 3. Key Files and Responsibilities

- `lib/main.dart` — app entry (Auth wrapper is used to route to login/home/admin pages).
- `lib/Firebase/auth_controller.dart` — binds Firebase user stream and exposes login/register/logout functions used by UI.
- `lib/homepage/login_page.dart` — login UI and voice-assisted login/normalization logic; plays beep fallback asset when native beep fails (asset path referenced in code: `lib/assets/sounds/beep_short.mp3`).
- `lib/registration/user_registration.dart` + `lib/controllers/sign_up_controller.dart` — voice-driven onboarding flow; orchestrates field-by-field capture, validations, and final submission. Creates Firebase Auth user then writes a Firestore `users/{uid}` document (see Firestore shapes below). On Firestore write failure it attempts to clean up the created Auth user.
- `lib/mic_widget/service_speech.dart` (SpeechService) — shared speech helpers: startListening, listenForCommand, playBeep, listenForYesNo, spellOutText, active field management, token normalization for emails and passwords, and a command handler used during onboarding.
- `lib/appointment/appointment_page.dart` + `lib/controllers/appointment_controller.dart` — appointment UI and voice booking orchestration. Implements a robust voice-based stepper: choose day → choose period (Morning/Afternoon/Evening) → choose time slot → confirm. Supports editing time/reason, and a two-step cancellation flow.
- `lib/appointment/app_widget/appointment_service_speech.dart` — appointment-specific speech commands, voice passphrase enrollment/verification using Firestore, and a Levenshtein-based fuzzy matcher for passphrase verification.
- `lib/homepage/profile_page.dart` — profile viewer that streams `users/{uid}`; displays name/surname/email/contact/createdAt and provides sign-out.
- `lib/admin/admin_homepage.dart` — admin landing page (routing uses `AuthWrapper` to check for admin via email contains `@admin`).

## 4. Voice & Audio Orchestration (Behavioral Contract)

This app follows a consistent cue→listen pattern to avoid recording TTS:

1. Play a short beep (native MethodChannel `voicecare/audio`) via `invokeMethod('playBeep')`.
2. Wait a short delay (typically 140–300 ms) to allow the beep to finish.
3. Initialize STT and call `listen()` for a context-appropriate timeout.

Timeout/behavioral details pulled from the controllers:

- Homepage navigation / quick listens: ~4 seconds timeout.
- Appointment confirmation & some appointment listens: 5–6+ seconds (confirmation uses ListenMode.confirmation).
- General field dictation: larger windows (e.g., 12s) in `startListening(dictation: true)`.

Signals & flags in `AppointmentController` that affect flow:

- `voiceFlowCancelled`, `voiceFlowCancellingWithAnnounce` — used to communicate cancellation and whether a cancellation announcement is in-flight. Cancel flows stop STT/TTS as appropriate.
- `isVoiceFlowRunning`, `isVoiceFlowActive` — basic state for UI.

Two-step cancellation flow (appointment):

1. System finds the latest appointment for the user.
1. It speaks the appointment summary and asks confirmation ("Do you want to cancel it?").
1. If the user answers yes (listens to yes/no), the controller calls helper(s) to release matching timeslot(s) in the `timeslots` collection and deletes the appointment document.

End of appendix.

Edge cases & notes

- The controller uses `stopFlow` to allow double-tap on the Name field (via `VoiceFormField`) to cancel voice onboarding and permit manual typing. The ID field was commented out in some versions.
- Consider exposing a single public method to abort onboarding cleanly from the app shell or route pop.

Primary class: `SpeechService extends GetxService`

Selected fields

- `_speech: SpeechToText` — private STT instance used by the service
- `flutterTts: FlutterTts` — TTS instance
- `isListening: RxBool` — reactive flag
- `speechText: RxString` — last recognized text
- `wasMicPressed: RxBool` — UI-driven flag set by mic widgets
- `_allowListeningAfter: DateTime?` — guard to ignore STT results until a time to avoid capturing TTS
- `activeController: TextEditingController?` — currently active field controller (if editing)
- `activeFieldName: String?` — label of the active field
- `_audioChannel: MethodChannel('voicecare/audio')` — native beep channel

Key public methods (summary)

- `_playNativeBeep()` → `Future<void>`
  - Invokes `_audioChannel.invokeMethod('playBeep')`. Exceptions are swallowed so callers can fall back to TTS or asset playback.

- `playBeep()` → `Future<void>`
  - Public wrapper that attempts native beep then waits ~300 ms. Falls back to speaking a short TTS cue if native beep fails.

- `startListening({bool dictation = false, int listenSeconds = 12})` → `Future<void>`
  - Initializes STT if necessary, plays the native beep and waits ~150 ms, starts `_speech.listen(...)` with appropriate `listenFor` handlers. If `activeController` is set, final results are written into `activeController.text` (with optional formatting). Updates `isListening` and `speechText` during lifecycle.

- `listenForCommand({required Function(String) onResult})` → `Future<void>`
  - Sets up a short confirmation-style listening session and invokes the `onResult` callback with final text.

- `listenForYesNo(String field, TextEditingController controller)` → `Future<bool>`
  - Specialized short listen (timeout ~5s) returning true for affirmative responses and false otherwise; uses completer+timeout pattern.

- `_handleCommand(String recognized)` → `Future<void>` (internal)
  - Command dispatcher for onboarding: handles `submit`, `restart registration`, `repeat`, `edit`, `clear`, `go to` and other phrases. Uses `Get.find<SignUpController>()` to interact with sign-up flow.

- `activateFieldForEditing(String field, TextEditingController controller)` → `Future<void>`
  - Sets `activeController`/`activeFieldName`, navigates focus (via `SignUpController`), speaks "Editing the field", waits for TTS completion and a guard interval, then allows STT to start.

- `stopListening()` → `Future<void>`
  - Stops STT if active, sets `isListening=false`, clears `speechText`.

- `spellOutText(String input)` → `Future<void>`
  - Speaks each character of `input` separately (useful for spelling emails or IDs).

- `playBeepAndListenForCommands()` → `Future<void>`
  - Convenience: plays beep via `_playNativeBeep()` then starts a command-mode `listen()` session.

- `listenForCommandWithTimeout({int timeoutSeconds = 6})` → `Future<String?>`
  - Returns recognized command or `null` on timeout. Plays beep, listens in confirmation mode, and resolves a completer.

Normalization & helper utilities (important to test)

- `_normalizeField(String raw)` — maps spoken field names to canonical controller keys (e.g., "contact number" → `contactnumber`).
- `_tokenToDigit(String t)` — maps spoken digit tokens ("one", "oh", "zero") to numeric characters.
- `_spokenToDigits(String recognized)` — converts a spaced digit sequence into a compact numeric string, preserving repeated tokens when necessary.
- `_processPasswordSpoken(String recognized)` — transforms spoken password tokens into a password string: handles tokens like "capital", numeric words, and collapses spaces.

Interactions & side effects

- Interacts with `SignUpController` for onboarding command handling.
- Often used by UI widgets (e.g., `MicButton`, `VoiceFormField`) via `Get.find<SpeechService>()`.
- Tolerant of native channel failures; falls back to TTS or asset playback.

Testing recommendations

- Add unit tests for `_spokenToDigits`, `_tokenToDigit`, `_normalizeField`, and `_processPasswordSpoken`.

---

### File: `lib/controllers/appointment_controller.dart` (AppointmentController)

Purpose

- Orchestrates the voice-driven appointment booking flow: listens for available timeslots, groups slots by period, guides the user through day/period/time/reason selection, confirms bookings, submits appointments to Firestore, and supports two-step cancellation.

Packages used

- `cloud_firestore`, `firebase_auth`, `speech_to_text`, `flutter_tts`, `intl`, `flutter/services.dart` (MethodChannel 'voicecare/audio')

Selected fields

- `flutterTts: FlutterTts` — TTS instance used for spoken prompts
- `_speech: SpeechToText` — STT instance used only by this controller
- `_audioChannel = MethodChannel('voicecare/audio')` — native beep
- `slotsByPeriod: RxMap<String, List<Map<String,dynamic>>>` — grouped slots for selected date
- `_timeToDocId: Map<String,String>` — maps 'HH:mm' → Firestore docId
- `selectedDate: Rx<DateTime>`, `selectedTime: Rx<String?>`, `reasonController: Rx<TextEditingController>`
- Control flags: `isVoiceFlowActive`, `isVoiceFlowRunning`, `voiceFlowCancelled`, `voiceFlowCancellingWithAnnounce`

Key methods

- `_listenSlotsForSelectedDate()`
  - Starts a Firestore listener on `timeslots` for the formatted `selectedDate` (yyyy-MM-dd). Updates `slotsByPeriod` with maps `{ 'time': 'HH:mm', 'available': bool, 'docId': '<id>' }` and refreshes `_timeToDocId` for quick lookup.

- `_determinePeriod(String periodRaw, String normalizedTime)`
  - Returns `"Morning" | "Afternoon" | "Evening"`. Uses `periodRaw` if contains the keywords, otherwise infers period from hour.

- `_normalizeRawTimeTo24(String raw)`
  - Normalizes many time notations into `HH:mm` (24-hour) string; returns `null` on parse failure.

- `listenForSpeech({int timeoutSeconds = 6})` → `Future<String?>`
  - Plays native beep (via `_audioChannel`) with a short delay, starts STT, and waits for a final STT result or timeout. Uses `_isInitializing` and `_speech.isListening` guards to avoid concurrent STT inits.

- `startVoiceBookingFlow()`
  - Full booking orchestration: speak intro, listen for day (`_listenForDayInRange`), period (`_listenForPeriod`), time (`_listenForTime`), optionally edit reason/time, confirm (`_confirmBooking`) and `submitAppointment()`.
  - At await points calls `_handleIfCancelled()` to abort if UI requested cancellation.

- `_handleIfCancelled()` → `Future<bool>`
  - If `voiceFlowCancelled` is set, stops TTS/STT (unless `voiceFlowCancellingWithAnnounce` guarded) and returns `true` so callers can abort the flow.

- `cancelVoiceBookingFlow()` / `cancelVoiceBookingFlowWithAnnouncement()` / `stopAllFlowsSilently()`
  - Cancellation helpers invoked by UI (e.g., double-tap date chips). The "WithAnnouncement" variant allows speaking an explanatory TTS message while marking flow cancelled.

- `_listenForDayInRange(start,end)`, `_listenForPeriod()`, `_listenForTime(slots)`
  - Helpers that guide specific steps with listening prompts, parsing, and validation against available `slotsByPeriod`.

- `listenYesNo()`
  - Short confirm/deny listen used in confirmations.

- `_confirmBooking()`
  - Reads back chosen date/time/reason (via `formatTimeForSpeech` and `_friendlyDate`), asks for confirmation, and either proceeds or calls edit flows.

- `submitAppointment()`
  - Writes to `appointments` and updates `timeslots` (availability). Returns `true` on success.

- `promptCancelLatestAppointment()`
  - Finds user's latest appointment (Firestore), speaks it, asks confirmation, and if confirmed releases matching timeslot(s) and deletes the appointment.

- `_releaseTimeslotForAppointmentData(...)`
  - Finds timeslot docs matching appointment date/time and marks them available again or adjusts capacity.

Helpers

- `formatTimeForSpeech(String time24)` — Converts `HH:mm` to human-friendly spoken string using `_numToWords`.
- `_numToWords(int)` — number→words conversion for 0..59.
- `_normalizeTime(String)` and `_parseFlexibleDate(...)` — robust spoken-time/date normalization/parsing.

Concurrency & correctness notes

- The controller cancels and re-attaches listeners to avoid stale state. For strong reservation semantics, prefer server-side transactions when claiming timeslots to avoid race conditions.

---

### File: `lib/appointment/app_widget/appointment_service_speech.dart` (AppointmentSpeechService)

Purpose

- Appointment-page specific speech helper. Handles appointment commands, plays beeps, delegates to shared `SpeechService` when available, and implements client-side voice passphrase enrollment/verification using Levenshtein distance.

Packages used

- `speech_to_text`, `flutter_tts`, `cloud_firestore`, `firebase_auth`, `get`, `flutter/services.dart`

Key methods

- `_handleCommand(String command)`
  - Lightweight command dispatcher for the appointment context: recognizes `book appointment`, `cancel appointment`, `reschedule`, `go back`, `restart process`, `repeat time` and calls `AppointmentController` methods like `editsTimeFlow()` when needed.

- `listenForCommand()`
  - Plays native beep (`_appointmentAudioChannel.invokeMethod('playBeep')`), initializes STT and starts a `listen()` in confirmation mode. Sets `isListening` true after start.

- `listenForCommandWithTimeout({int timeoutSeconds = 6})` → `Future<String?>`
  - Plays a pre-listen beep, initializes STT, uses a `Timer` to enforce a timeout, and returns recognized text or `null` on timeout.

- `playBeepOnly({int delayMs = 160})`
  - Delegates to `SpeechService.playBeep()` when registered, else invokes `_appointmentAudioChannel.invokeMethod('playBeep')` directly as fallback.

- `enrollPassphraseToFirestore(String passphrase, {int minWords = 3})` → `Future<bool>`
  - Normalizes phrase using `_normalizePhrase()` and writes canonical `voiceNormalized` to `users/{uid}` if it meets `minWords` requirement.

- `verifyVoiceWithFirestore({int timeoutSeconds = 6, int maxDistance = 2})` → `Future<bool>`
  - Reads stored `voiceNormalized`, listens for a new passphrase via `listenForCommandWithTimeout`, normalizes both strings, computes `_levenshtein(a,b)` and accepts match if `distance <= maxDistance` or `relative distance <= 0.25`.

Helpers

- `_normalizePhrase(String)`, `_levenshtein(String a, String b)` — canonicalization and edit-distance functions.

Security note

- Consider storing a secure derived representation of the normalized phrase (hash) rather than plaintext in Firestore for better security.

---

### File: `lib/Firebase/auth_wrapper.dart` (AuthWrapper)

Purpose

- Routes the root of the app depending on authentication state and admin detection. Uses `AuthController` (GetX) to watch the current Firebase `User` stream.

Behavior

- Observes `authController.firebaseUser.value` in an `Obx`. When non-null, lowercases `user.email` and if it contains `@admin` returns `AdminHomePage`, else `HomePage`. When null, returns `LoginPage`.

Note

- Admin detection is currently email-substring based; prefer roles/claims in production.

---

### File: `lib/controllers/sign_up_controller.dart` (SignUpController)

Purpose

- Coordinates voice onboarding/registration, field focus management, validation, and submission to Firebase Auth + Firestore.

Packages used

- `get`, `cloud_firestore`, `firebase_auth`, `voicecare/mic_widget/service_speech.dart`

Selected fields

- Controllers for fields: `name`, `surname`, `email`, `contactnumber`, `password`
- FocusNodes: `nameNode`, `surnameNode`, `emailNode`, `contactnumberNode`, `passwordNode`
- `activeController: Rxn<TextEditingController>` — which field is currently active
- `speechService = Get.find<SpeechService>()`
- `stopFlow: RxBool` — when true, voice onboarding is stopped and manual typing is enabled

Key methods

- `getNodeForField(String field)`
  - Returns the matching `FocusNode` for a canonical field key.

- `listenForCommand()` / `listenForCommandMode()`
  - Enter command mode: call `speechService.listenForCommand` or `listenCommand` and route results to `handleVoiceCommand()`.

- `handleVoiceCommand(String command)`
  - Normalizes commands and supports `go to <field>` for fields, `restart registration` and other high-level commands. Activates field focus via `activateField` helper.

- `listenToUser({bool format = true})`
  - For active field, delegates to `speechService.startListening(dictation:true)`, waits for completion, and formats text as needed (email/phone normalization).

- `goToField(TextEditingController controller, FocusNode node, String fieldName)`
  - Sets `activeController`, `speechService.setActiveController`, resets `wasMicPressed`, requests focus, and speaks "Editing the field".

- Validation helpers (`validateEmail`, `validateName`, `validateSurname`, `validateContactNumber`, `validatePassword`)
  - Return `String?` errors or `null`. `validatePassword` enforces password strength rules (min length, at least two digits, etc.).

- `startVoiceOnboarding()`
  - Orchestrated flow prompting for fields sequentially, repeating fields for confirmation, allowing edits, and eventually calling `submitRegistration()`.

- `repeatAllFieldsAndAskEdit(List<Map<String,dynamic>> fields)`
  - Reads back fields via TTS and asks if the user wants to edit any field.

- `_collectValidationErrors()`
  - Collects and returns validation errors for all fields.

- `submitRegistration()`
  - Validates inputs, creates Firebase Auth user, writes Firestore `users/{uid}` with `uid`, `name`, `surname`, `email`, `contactNumber`, `createdAt`, attempts to delete the auth user if Firestore write fails, and navigates to `HomePage` on success.

- `stopAllFlows()`
  - Cancels voice flows, stops TTS, and clears active controller.

Notes & UX

- Double-tap on the `Name` field is a UX escape hatch (handled by `VoiceFormField`) that sets `stopFlow = true` to allow typing.

---

### File: `lib/widgets/voice_form_field.dart` (VoiceFormField)

Purpose

- A `TextFormField` wrapper tuned for voice interaction: shows glowing mic prefix while active, manages focus and `activeController` in `SignUpController`, and supports double-tap to enable typing / stop voice flow.

Constructor

- `VoiceFormField({ controller, validator, labelText, prefixIcon, readOnly=false, focusNode, obscureText=false })`

Behavior

- Focus listener: on focus gained, if `stopFlow` is false the widget sets `speechService` active controller and updates the sign-up controller's `activeController`.
- Double-tap: if `labelText.toLowerCase() == 'name'` then the whole voice flow is stopped and keyboard is enabled; otherwise double-tap just focuses the field.
- Visual glow: `AvatarGlow` wraps the prefix icon when field is active and listening.

Accessibility note

- Keep the double-tap escape consistent and communicate the change to users via TTS and UI state.

---

### File: `pubspec.yaml` (dependencies summary)

Purpose

- Lists SDK constraints, package dependencies, and assets used by the project.

Key packages

- `get`, `avatar_glow`, `speech_to_text`, `flutter_tts`, `firebase_core`, `firebase_auth`, `cloud_firestore`, `audioplayers`

Assets

- `lib/assets/sounds/beep_short.mp3` — asset fallback beep used by `login_page.dart` and other places when native channel fails.

Note

- Keep versions aligned with the Flutter SDK and test audio/STT/TTS compatibility when upgrading.

---

### File: `lib/admin/timeslots.dart` (AdminTimeslotPage)

Purpose

- Admin utility to create/edit timeslots in Firestore and view the existing schedule. Uses `timeslots` collection fields `date`, `startTime`, `endTime`, `capacity`, `isActive`, `available`, and `period`.

Key method: `_saveTimeslot()`

- Validates form fields, composes `date` as 'yyyy-MM-dd', converts `TimeOfDay` to zero-padded `HH:mm` strings, and writes a document to `timeslots` with fields: `date`, `startTime`, `endTime`, `capacity`, `isActive: true`, `available: true`, `period`.
- On success shows a SnackBar and clears form fields.

UI

- A `StreamBuilder` shows existing timeslots from Firestore ordered by `date` and `startTime`.

Production notes

- Add edit/delete controls and consider server-side validation/transactions for bulk operations.

---

If you'd like, I can now:

- generate a `DEVELOPER_NOTES.md` summarizing this appendix as a concise file→function map (one-liners per method), or
- create unit tests for the normalization helpers in `service_speech.dart`, or
- expand any method documentation here into a snippet showing the exact parameter checking and return behavior from the current implementation.

End of appendix.

Edge cases & notes

- The controller uses `stopFlow` to allow double-tap on the Name field (via `VoiceFormField`) to cancel voice onboarding and permit manual typing. The ID field was commented out in some versions.
- Consider exposing a single public method to abort onboarding cleanly from the app shell or route pop.

### File: `lib/widgets/voice_form_field.dart` (VoiceFormField)

Purpose

- A wrapped `TextFormField` designed for voice-driven input. Integrates with `SignUpController` and `SpeechService` to provide a glowing mic icon when active/listening, double-tap-to-enable-typing semantics, and automatic focus/activeController management.

Packages used

- `avatar_glow`, `get`, `flutter/material.dart`

Constructor arguments

- controller: TextEditingController? — target controller
- validator: String? Function(String?)? — validation callback
- labelText: String — field label shown in UI
- prefixIcon: Widget? — icon to show
- readOnly: bool — whether the field should be read-only when voice flow is active
- focusNode: FocusNode? — optional external focus node
- obscureText: bool — for password fields

Key behavior

- on focus gained: if `SignUpController.stopFlow` is false, sets `speechService` active controller and marks activeController in sign-up controller; this prepares field for voice dictation.
- on focus lost: clears active controller if it matches.
- onDoubleTap: if label is "Name", then stop the entire flow (set `stopFlow.value = true`) and speak "Voice input stopped." and request focus, enabling typing. For other fields, it simply shows the keyboard (requests focus).
- The widget observes `speechService.isListening` and `wasMicPressed` to decide whether to show an `AvatarGlow` around the prefix icon.

Accessibility & UX notes

- Double-tap to stop voice onboarding is a critical UX escape hatch; keep this behavior consistent across similar form fields.

### File: `pubspec.yaml` (dependencies)

Purpose

- Project manifest listing SDK, dependencies, assets and versions.

Key dependencies (as observed):

- get: ^4.7.2 — state management/DI
- avatar_glow: ^3.0.1 — UI glow effect for mic and icon
- speech_to_text: ^7.0.0 — STT client
- flutter_tts: ^4.2.3 — TTS client
- firebase_core, firebase_auth, cloud_firestore — Firebase services
- audioplayers: ^6.5.1 — audio playback (asset fallback)

Assets

- `lib/assets/sounds/beep_short.mp3` — used as a fallback beep audio

Note

- Keep dependency versions pinned or periodically audited. For speech packages, ensure compatibility with the Flutter SDK version in `environment.sdk: ^3.5.4`.

### File: `lib/admin/timeslots.dart` (AdminTimeslotPage)

Purpose

- Admin UI to create and manage timeslot documents in Firestore. Provides a simple form for creating timeslots (date, start/end, period, capacity) and a stream that lists existing timeslots.

Packages used

- `cloud_firestore`, `intl` for date formatting, `flutter/material.dart`

Key methods & behavior

- Future<void> _saveTimeslot()
  - Validates the form, ensures date/time/period selected, formats date as 'yyyy-MM-dd', constructs startTime/endTime strings with zero-padded hour/minutes, and calls `FirebaseFirestore.instance.collection('timeslots').add({...})` with fields: `date`, `startTime`, `endTime`, `capacity`, `isActive`, `available`, `period`.
  - Shows a SnackBar on success and clears form state.

- build(BuildContext): builds the admin form and a `StreamBuilder` that listens to `timeslots` collection ordered by date then startTime, and shows a list of timeslots with an icon indicating `isActive`.
