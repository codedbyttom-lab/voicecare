VoiceCare — User Manual v1.4
===========================

Last updated: 2025-10-05

Purpose
-------

This manual documents the user-facing behavior implemented in the current codebase. The file below focuses on the three primary entry screens in the requested order: Login → User Registration → Home. Each section highlights exact behaviors and helpful tips derived from the app sources.

Login (sign in)
---------------

Overview

- Open the app,  When the Login screen appears the app speaks a short welcome prompt and then plays a beep before listening for a reply.

What the voice flow does:

- Initial prompt: "Welcome to voice care, please double tap each field to use the keyboard. Would you like to login or register?" After TTS completes the app plays a short beep and starts a short listen.

- Spelled email capture: the login flow asks you to spell your email letter-by-letter followed by the domain. The code normalizes spoken tokens:
  - `dot` → `.`
  - `at` → `@`
  - `underscore` → `_`
  - `hyphen` / `dash` → `-`
  - `plus` → `+`

- Password capture: the voice flow accepts casing tokens such as "capital X" / "uppercase X" to indicate uppercase letters; it attempts to apply those tokens when building the password string. For privacy the app does not speak back voice-entered passwords.

- Timeouts observed in code:
  - Spelled email capture: up to ~10 seconds (longer single capture).
  - Short command/listen sessions: ~4–6 seconds depending on context.

When to prefer typing

- For passwords and sensitive data prefer typing. You can double-tap any field to stop voice onboarding and open the keyboard (double-tap also stops TTS/STT in most screens).

Edge cases and tips

- If the voice-captured password fails sign-in, re-enter the password manually in the field and try again.
- If STT or audio playback fails, restart the app and ensure microphone permission is granted.

User Registration (sign up)
---------------------------

Overview

- The registration screen is voice-enabled and also supports typed input via double-tap on any field.

Voice onboarding

- The registration flow begins voice onboarding immediately after the page loads. The app will prompt you for fields and play beeps before listening.

Fields collected:

- `name`
- `surname`
- `email`
- `contactNumber`

How to edit fields via keyboard

- Each form field is voice-driven by default and set to read-only. To type instead:
  1. Double-tap the field you want to edit (e.g., Name, Email, Contact Number, Password).

How to edit fields via voice

- Press the mic button and say 'repeat' followed by the name of the field you'd like repeated

- Press the mic button and say 'edit' followed by the name of the field you'd like to edit.

Submit (what the code does)

- Press the `Submit` button to run a non-speaking registration path. The code does the following in order:
  1. Validates the form client-side using the controller's validators.
  2. Creates the auth user.
  3. If the Firestore write fails the code attempts to delete the newly created auth user (cleanup) to avoid orphaned accounts and shows a snackbar error.
  4. On success it shows a success snackbar and navigates to Home.

When to prefer typing during registration

- For passwords and any complex email/local-part, use double-tap and type for speed and accuracy.

Home (main screen)
------------------

Overview

- Home contains the main quick actions (commands): `Book Appointment`, `View Appointments`, `Profile`, and `Help`. The central mic button is used for quick voice commands and to start longer voice flows.

Mic button behavior (homepage)

- Visual feedback: when the mic is pressed or STT is active the UI shows an avatar glow.

- Beep before listen: the home mic plays a short beep prior to starting STT.

- Typical listen timeout: the homepage single-shot mic listener uses ~4 seconds before timing out and returning the latest partial result.

Single-shot commands supported on Home (examples)

- Say `help` to hear available commands.
- Say `book appointment` to start the booking flow.
- Say `view appointments` to open your bookings.
- Say `profile` to open the Profile screen.

Safe handling when navigating away

- If the mic/voice flow is active and you navigate away, the code ensures the voice service is stopped and the UI flags are reset to avoid lingering listening or animation.

Troubleshooting quick checklist

- Microphone permission: Settings → Apps → VoiceCare → Permissions.
- Ensure device volume is up; embedded beep asset and native channel must be available for best UX.
- Prefer typing when in noisy environments or when entering passwords.

Appointment page (booking flow & timeslots)
------------------------------------------

Overview

- The Appointment page is where you pick a date, select an available timeslot, enter a reason, and submit the booking. The page launches the voice booking flow automatically (see `AppointmentPage.initState`) and also provides visual pickers and touch controls.

Layout and controls

- Date selector: a horizontally-scrollable date row shows the next 7 days. Tap a date to load its timeslots. Single-tap selects; double-tap cancels the active voice booking flow (see double-tap behavior below).

- Timeslots: available times are grouped into Morning / Afternoon / Evening sections. Each timeslot appears as a pill; unavailable slots are grayed out and cannot be selected.

- Reason: a Reason field below the slots collects a short reason for the appointment.

- Mic and Submit: the bottom area contains the appointment-specific mic button (`AppointmentMicButton`) and a `Submit` button. The mic also plays a short beep before listening and uses a confirmation-style listen mode.

Voice booking flow (high-level)

1. The booking flow is started automatically when the page opens (controller.startVoiceBookingFlow).

2. The controller speaks: a welcome and guidance prompt, then asks for a day within a 7-day window (it gives an example day). The code listens for a day phrase and normalizes many spoken variants.

3. After the day is accepted the controller asks for a period ("Morning, afternoon, or evening?") and then lists available times for the chosen period.

4. The controller then prompts: "Please say your preferred time." It listens (with retries) and will accept many spoken time formats (e.g., "one thirty pm", "13 30", "thirteen thirty").

5. The controller asks for confirmation. If you say `yes` the booking proceeds and the controller attempts to write an appointment document to Firestore; if you say `no` it aborts and returns you to Home.

Timeslot selection and release behavior

- Selection: tapping an available timeslot sets that time for submission. During the voice flow the code maps recognized spoken times to the closest available slot using normalization helpers.

- Release on cancel: when an appointment is cancelled the controller attempts to release the associated timeslot(s). The helper prefers a stored `timeslotId` on the appointment document; otherwise it looks up timeslots by `date` + `time` or `startTime` variants and marks them available again.

- Double-tapping a date chip on the Appointment page triggers an immediate cancellation of the active voice flow.

Submit flow (what happens on `Submit`)

- The `Submit` button:
  1. Validates that a time is selected.
  2. Builds an appointment document including `bookedBy` (uid), `date`, `time`, `createdAt` and optional `reason` and `timeslotId`.
  3. Writes the appointment document to the Database and attempts to mark the timeslot document (if known) as unavailable atomically where possible.
  4. Returns success/failure to the UI and shows a Snackbar accordingly.

Edge cases and helpful notes

- If slots change under you (another user booked the timeslot) the controller will detect unavailable slots and prompt you to pick another time.

- The voice flow is cancel-safe: the controller clears TTS/STT immediately. After cancellation the app returns you to Home.

Profile (view & behavior)
-------------------------

- Open `Profile` from Home to view your account information. The screen displays an avatar (if a `photoURL` exists), a display name, email, phone, and the account creation time.

- Actions available:
  - `Sign out` — calls FirebaseAuth signOut and navigates to the Login screen. If sign-out fails the UI shows a Snackbar with the error.
  - `Back to Home` — returns to the Home screen.

- Editability: the Profile screen is read-only (no inline edit controls are present in `profile_page.dart`). To change stored profile fields you must use any dedicated account-editing screen provided elsewhere in the app or update the Firestore document by other means (support, admin, or a future edit UI).

- Privacy: the page only shows data when a user is signed in; if not signed in the page displays "Not signed in".

- Troubleshooting notes specific to Profile:
  - If profile fields are stale, ensure you're signed into the correct account.
  - If `createdAt` shows `Unknown`, the account document may have been created before the code wrote a server timestamp; contact support if this is important.

End of Profile section

Known Limitations

Network Dependence

- Voice recognition and speech feedback require an active internet connection.

- Offline mode currently provides limited feedback (only basic text alerts).

Language Support

- The system currently supports English only for both speech input and output.

- Commands or names spoken in other languages may not be recognized accurately.

Speech Recognition Accuracy

- Accuracy may vary depending on background noise, microphone quality, and user accent.

- Users should speak clearly and at a moderate pace for best results.

Limited Command Set

- Only predefined voice commands such as “repeat,” “edit,” “clear name,” or navigation prompts are supported.

- Natural or unrecognized speech outside of these commands may be ignored.

Password Privacy Restriction

- For security, the system does not repeat or audibly confirm spoken passwords when logging in .

- Users must rely on confirmation tones or silent validation feedback.

Accessibility Scope

- Designed primarily for visually impaired users, so some visual UI elements may appear simplified.

- Advanced accessibility gestures (e.g., screen readers) are partially supported depending on device settings.

Voice Flow Control

- During guided registration, users cannot interrupt or skip steps mid-process.

- Corrections can only be made after each field is confirmed.

Platform Limitation

- Currently available only as a mobile application.

- Desktop or web platforms are not yet supported.

Firebase Connectivity

- Any temporary loss of Firebase connection may delay data saving or retrieval.

- The system retries automatically but may require manual resubmission if the issue persists.

User Training Requirement

- New users may need a short adjustment period to learn voice commands and app flow.

-Guidance prompts help, but familiarity improves accuracy and navigation speed.
