# 🚀 Campus Path Tracker
### AI-Powered Real-Time Campus Proximity and Safety System

---

## 📌 Overview

Campus Path Tracker is a real-time campus safety and proximity awareness system designed to help students locate friends during partial network failures such as weak signals, one-way communication, or inaudible calls.

The system enables users to:
- Search friends by Name
- Identify approximate campus locations
- Detect nearby trusted users
- Receive AI-powered helper suggestions

This project combines:

- 📡 Real-Time Location Tracking (GPS + Wi-Fi)
- 🧠 AI-Based Decision Making (Claude / Anthropic API)
- 🔔 Proximity-Based Alerts
- 🌐 App-Based User Interface (Flutter)

to improve communication and student safety inside university campuses.

---

## ✅ Implementation Status

| Feature | Status |
|---------|--------|
| Firebase project setup & Firestore security rules (6 collections) | ✅ Implemented |
| Android permissions (location, microphone, Bluetooth, internet) | ✅ Implemented |
| All Flutter dependencies configured in pubspec.yaml | ✅ Implemented |
| User registration with EmailJS OTP verification | ✅ Implemented |
| Firebase Auth login / forgot password / session management | ✅ Implemented |
| Real-time GPS tracking with distance-filter trigger (10 m) | ✅ Implemented |
| Firestore location sync (`location`, `lastLocation`, `isOnline`, `lastSeen`) | ✅ Implemented |
| App lifecycle observer (auto offline on background/close) | ✅ Implemented |
| Nearby user detection with `VerilogDistanceRanker` (4-tier proximity) | ✅ Implemented |
| Live map view (`flutter_map` + OpenStreetMap + `latlong2`) | ✅ Implemented |
| Find People tab — name-based search with connection request flow | ✅ Implemented |
| Connections tab — real-time list with online/offline status | ✅ Implemented |
| In-app text chat (`ChatService` + Firestore `/chats` collection) | ✅ Implemented |
| Peer-to-peer voice calls via `flutter_webrtc` + Firebase signaling | ✅ Implemented |
| Incoming call listener with overlay push across all screens | ✅ Implemented |
| AI helper recommendations via Claude API (`AiDecisionEngine`) | ✅ Implemented |
| Profile edit screen (role-aware: Student / Faculty / Others) | ✅ Implemented |
| Person location screen (track a specific user on map) | ✅ Implemented |

---

## 🚨 Problem Statement

### The Context

Large university campuses are densely populated environments — spanning multiple buildings, open grounds, labs, and hostels — where hundreds to thousands of students move simultaneously throughout the day. Despite the prevalence of smartphones, **reliable communication on campus remains a critical unsolved problem.**

### The Core Problem

Campus infrastructure creates predictable **dead zones**: thick concrete walls in old buildings, underground labs, crowded seminar halls, and open grounds far from cell towers all degrade mobile signal quality. In these conditions, students face:

- 📵 **Dropped or one-way calls** — the caller hears ringing, but the recipient never receives it
- 💬 **Delayed message delivery** — SMS and app messages queue and arrive minutes later, or not at all
- 📍 **Zero location awareness** — neither party knows where the other is or how far away they are
- 🆘 **Slow emergency response** — during accidents, medical events, or security incidents, finding a specific person or the nearest available helper becomes chaotic and time-consuming

### Why This Matters

Consider a common real scenario:

> A student is injured near the campus ground. Their friend tries calling — the call drops. They send a message — it doesn't deliver. They don't know the student's exact location or who is nearby to help. Minutes pass before assistance arrives.

This delay — caused not by distance but by **communication failure** — is entirely preventable with the right system in place.

### The Gap in Existing Solutions

General-purpose applications such as WhatsApp, Google Maps, and Find My Friends are designed for open internet environments. They fail in campus dead zones because:

| Limitation | Impact |
|------------|--------|
| Depend on stable internet/cellular | Fail exactly when needed most |
| No campus-specific location context | Can't identify "Block B, Room 204" or "Near the canteen" |
| No proximity-based user discovery | Can't surface who is physically nearby right now |
| No intelligent helper routing | Don't suggest the closest available trusted person |
| No emergency-aware logic | Treat all communication equally — no urgency prioritization |

### The Solution

**Campus Path Tracker** addresses this gap by combining real-time GPS tracking, Firebase-backed proximity detection, and AI-powered helper recommendations into a single campus-aware system. It is designed to function under degraded network conditions and provide **actionable location intelligence** — not just raw coordinates, but context: *who is near, how far, and who can help right now.*

---

## 🎯 Objectives

- ✅ Enable real-time campus location visibility
- ✅ Detect nearby trusted users
- ✅ Provide AI-based helper recommendations
- ✅ Support communication during low-signal conditions
- ✅ Improve campus safety and emergency response

---

## ✨ Functional Requirements
## ✅ Functional Requirements
 
---
 
### FR1 — User Registration with EmailJS OTP Verification + Firebase Auth
 
**What the system does:**
 
- User selects a role (Student / Faculty / Others) and enters their name, email, and password on the `AuthScreen`
- A 6-digit OTP is generated client-side and dispatched via **EmailJS** (`api.emailjs.com/api/v1.0/email/send`) to the entered email address using service ID `service_dsy5vsd` and template ID `template_aerokdl`
- The OTP is stored server-side in Firestore at `email_otps/{email}` with `otp`, `createdAt`, and `expiresAt` (5-minute TTL); expired OTP documents are auto-deleted after a failed verification attempt
- Registration is blocked until the user enters the correct OTP (matched first against the in-memory generated value, then Firestore as fallback)
- After verification, `FirebaseAuth.createUserWithEmailAndPassword` creates the account, and a profile document is written to Firestore `users/{uid}` with role-specific fields:
  - **Student:** `firstName`, `lastName`, `email`, `phone`, `role`, `rollNumber`, `parentEmail`
  - **Faculty:** `firstName`, `lastName`, `email`, `phone`, `role`, `employeeId`
  - **Others:** `firstName`, `lastName`, `email`, `phone`, `role`
- Login uses `FirebaseAuth.signInWithEmailAndPassword`; an active session is detected on app launch via `authStateChanges()` stream and routes directly to `HomeScreen` without re-login
- Password reset sends a Firebase reset link via `sendPasswordResetEmail` through a dialog that captures the user's email address
- Logout marks `isOnline: false` and `lastSeen` in Firestore, stops GPS tracking, then calls `FirebaseAuth.signOut()`
**Acceptance criteria:** A new user can register, receive OTP by email, verify it, and reach `HomeScreen` within 60 seconds; profile written to Firestore `/users/{uid}`.
 
---
 
### FR2 — Real-Time GPS Tracking with 10m Distance Filter and Firestore Sync
 
**What the system does:**
 
- On first launch after login, the app requests `ACCESS_FINE_LOCATION` permission via the `permission_handler` package
- The `geolocator` package streams GPS positions using `LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)` — updates only fire when the user physically moves ≥ 10 metres, which prevents idle Firestore writes and conserves battery
- On every qualifying position update, the following fields are written to `users/{uid}` via `FirebaseFirestore.instance.collection('users').doc(uid).update(...)`:
  - `location` (GeoPoint — current position)
  - `lastLocation` (GeoPoint — retained as offline fallback)
  - `isOnline: true`
  - `lastSeen` (FieldValue.serverTimestamp)
  - `accuracy` (metres)
  - `speed` (m/s)
- `AppLifecycleObserver` (extends `WidgetsBindingObserver`) manages tracking lifecycle:
  - `AppLifecycleState.resumed` → `LocationService.startTracking(uid)` restarts the stream
  - `AppLifecycleState.paused` / `AppLifecycleState.detached` → stream cancelled; `isOnline: false` + `lastSeen` written to Firestore
**Acceptance criteria:** Location updates reflect on the map within 15 seconds of a user moving ≥ 10 metres.
 
---
 
### FR3 — Nearby User Detection with 4-Tier Proximity Classification and Interactive Map
 
**What the system does:**
 
- The `_NearbyTab` streams all documents from the Firestore `users` collection in real time and calculates distance from the current user's position to each other user using `Geolocator.distanceBetween()` (Haversine formula)
- `VerilogDistanceRanker.rank()` classifies each result into one of 4 priority tiers:
  | Tier | Distance Range | Badge Colour | Meaning |
  |------|---------------|--------------|---------|
  | `nearest` | < 100 m | 🟢 Green | Immediately reachable |
  | `close` | 100–499 m | 🔵 Blue | Nearby — can arrive quickly |
  | `moderate` | 500–1999 m | 🟡 Amber | On campus — reachable within minutes |
  | `far` | ≥ 2000 m | 🔴 Red | Far — last resort |
- The `_NearbyTab` renders an interactive **OpenStreetMap** tile map via `flutter_map` + `latlong2` with role-coloured, initialled markers for every user:
  - Green = self · Blue = Student · Purple = Faculty · Amber = Others · Grey = offline user
- Tapping a marker opens a dialog showing the user's name, role, online status, last-seen time, and reverse-geocoded place name (cached in-memory via `GeocodingHelper._cache` to avoid redundant geocoding calls)
- Offline users remain visible on the map at their `lastLocation` (fallback via the `displayLocation` getter: `lastLocation ?? location`)
- A scrollable ranked list below the map shows each user's distance text, proximity badge colour, and online/offline indicator
**Acceptance criteria:** Nearby users appear on the map within 5 seconds of opening `_NearbyTab`; each user shows the correct proximity tier badge.
 
---
 
### FR4 — Bidirectional Connection Management with Real-Time Notifications
 
**What the system does:**
 
- Any authenticated user can send a connection request from `_FindPeopleTab`; this writes to `connection_requests/{doc}` with fields: `fromUid`, `fromName`, `toUid`, `toName`, `status: 'pending'`, `createdAt`
- A notification badge on the `PeopleScreen` AppBar shows a live count of pending incoming requests via a Firestore stream filtered by `toUid == myUid` and `status == 'pending'`
- A bottom-sheet panel lists all pending requests with Accept and Decline buttons
- **Accepting** creates a symmetric document at `connections/{fromUid}_{toUid}` containing a `users: [uid1, uid2]` array and `createdAt`; **Declining** updates `status` to `'rejected'`
- Location viewing, in-app chat, and voice calls are gated behind a mutual connection check via `ConnectionService.areMutuallyConnected(myUid, otherUid)` — non-connected users see a "Location Access Restricted" screen instead of the live map
**Acceptance criteria:** A connection request is visible to the recipient in real time; accepting it results in both users appearing on each other's Nearby tab and gaining access to chat and location.
 
---
 
### FR5 — Campus-Wide User Search with Connection Status and Distance Display
 
**What the system does:**
 
- `_FindPeopleTab` streams all Firestore `users` documents and filters results client-side using a case-insensitive search field matching against `fullName`, `role`, `rollNumber`, and `email`
- Each result tile displays: name, role, roll number (if Student), online/offline dot indicator, last-seen time, and distance in metres/km (if already connected)
- If already connected: a **"View Location"** button navigates to `_PersonLocationScreen`
- If not connected and no request sent: a **"Connect"** button writes a connection request to Firestore; after tapping it changes to an orange **"Requested"** chip
- Connection and request state is checked per tile via `ConnectionService.areMutuallyConnected` and a `connection_requests` Firestore query, then cached per session to limit reads
**Acceptance criteria:** Search results appear within 2 seconds; connection state (connected / requested / none) is correctly reflected per tile.
 
---
 
### FR6 — AI-Powered Helper Recommendation via Claude API
 
**What the system does:**
 
- On `_PersonLocationScreen`, tapping **"Find Help"** collects up to 5 nearby connected users ranked by `VerilogDistanceRanker.rank()`
- `AiDecisionEngine.getSuggestions()` sends a structured prompt to the **Anthropic API** (`POST https://api.anthropic.com/v1/messages`, model `claude-sonnet-4-20250514`, `max_tokens: 1000`) with each nearby user's name, role, distance text, proximity tier, online status, and last-seen time
- The prompt instructs Claude to return a **JSON array only** (no markdown, no backticks); each item contains `uid`, `action` (`call` or `message`), `reason` (one sentence), and `messageTemplate` (ready-to-send text)
- The response is parsed into `AiSuggestion` objects and displayed as actionable suggestion cards showing: recommended person, their distance and location, Claude's reason, the message template, and a one-tap call or chat button
- If the API call fails or returns a non-200 status, a local fallback activates automatically: online users → `call`, offline users → `message` with a generic template
- The Anthropic API key is never hardcoded — it is loaded at runtime from a `.env` file via `flutter_dotenv`
**Acceptance criteria:** AI recommendation renders within 5 seconds; the recommended user is the closest available active connection; fallback activates without crashing if API is unreachable.
 
---
 
### FR7 — Peer-to-Peer Voice Calls via flutter_webrtc and Firestore Signalling
 
**What the system does:**
 
The `CallService` class implements a full WebRTC audio call lifecycle backed by Firestore signalling at `calls/{chatId}`:
 
1. **Caller** (`startCall`): captures microphone audio via `getUserMedia({audio: true, video: false})`, creates an `RTCPeerConnection`, generates an SDP offer, and writes `offer`, `callerUid`, `calleeUid`, `status: 'ringing'` to the call document; ICE candidates are written to the `callerCandidates` sub-collection
2. **Callee** (`answerCall`): reads the offer SDP, creates an SDP answer, writes it back with `status: 'active'`; ICE candidates are written to `calleeCandidates`
3. **STUN servers:** `stun.l.google.com:19302` and `stun1.l.google.com:19302`
4. **Hang-up** (`hangUp`): peer connection is closed, media stream is disposed, call document status set to `'ended'`
5. **Mute toggle** (`toggleMute`): enables/disables the local audio track without dropping the connection
6. The `InAppCallScreen` shows caller/callee name and role, a live call-duration timer (updates every second via `Timer.periodic`), mute button, and hang-up button
7. Required Android permissions: `RECORD_AUDIO`, `BLUETOOTH`, `BLUETOOTH_CONNECT` declared in `AndroidManifest.xml`
**Acceptance criteria:** Caller and callee establish two-way audio; mute and hang-up work; call status progresses idle → ringing → active → ended; remote hang-up dismisses the local call screen automatically.
 
---
 
### FR8 — Real-Time In-App Text Chat with Read Receipts and Unread Badges
 
**What the system does:**
 
- Messages are stored at `chats/{chatId}/messages` where `chatId` is the lexicographically sorted UID pair (`ChatService.chatId(a, b)` → `[a,b].sort().join('_')`)
- Each message document contains: `from` (uid), `text`, `ts` (server timestamp), `read` (bool)
- The `InAppChatScreen` streams messages ordered by `ts` ascending via `messageStream()` and auto-scrolls to the latest message on each update
- Sent messages are right-aligned in primary blue; received messages are left-aligned in white; timestamp is shown per bubble
- On opening a chat, `ChatService.markRead()` batch-updates all unread messages from the peer to `read: true` via a Firestore batch commit
- The `_ConnectionsTab` renders a live unread badge count per contact via `ChatService.unreadStream()` — a Firestore stream filtered by `from == peerUid` and `read == false`
- Every send also updates the parent `chats/{chatId}` document with `lastMessage`, `lastTs`, and `lastFrom`
**Acceptance criteria:** Messages appear in real time for both parties; read receipts clear on opening chat; unread badge count updates live on the Connections tab.
 
---
 
### FR9 — Global Incoming Call Listener with Root-Navigator Overlay
 
**What the system does:**
 
- `IncomingCallListener` is a `StatefulWidget` that wraps the entire `HomeScreen` Scaffold (not just the body), subscribing to the Firestore `calls` collection filtered by `calleeUid == currentUser.uid` and `status == 'ringing'`
- On detecting a ringing call, it fetches the caller's profile from Firestore and presents an `AlertDialog` using `Navigator.of(context, rootNavigator: true)` — this ensures the dialog appears above all navigation routes and tab stacks
- The dialog displays the caller's name, role, and initials avatar with **Answer** and **Decline** buttons
- **Answering** navigates to `InAppCallScreen(peer: caller, isOutgoing: false)` via `rootNavigator: true`
- **Declining** updates `status` to `'ended'` in the call Firestore document
- A `_dialogShown` guard prevents duplicate dialogs if the stream fires multiple times
**Acceptance criteria:** An incoming call triggers a full-screen overlay on the callee's device regardless of which tab or screen they are viewing.
 
---
 
### FR10 — App Lifecycle Observer with Automatic Online/Offline Management
 
**What the system does:**
 
- `AppLifecycleObserver extends WidgetsBindingObserver` is registered in `_CampusLocatorAppState` when a user is authenticated; deregistered on logout or app disposal
- `AppLifecycleState.resumed` → `LocationService.startTracking(uid)` restarts the GPS stream
- `AppLifecycleState.paused` or `AppLifecycleState.detached` → `LocationService.stopTracking()` cancels the stream; `LocationService.goOffline(uid)` writes `isOnline: false` + `lastSeen` to Firestore
- The same offline update fires on explicit logout before `FirebaseAuth.signOut()` is called
- Offline users continue to appear on all maps via the `displayLocation` getter (`lastLocation ?? location`) and the `LastSeenHelper.format()` utility
**Acceptance criteria:** Closing or backgrounding the app marks the user offline within seconds; reopening the app resumes tracking and marks them online automatically.
 
---
 
## ⚙️ Non-Functional Requirements
 
---
 
### NFR1 — Performance
 
- Location updates fire only on ≥ 10m physical movement (distance-filter stream, not a polling timer) — Firestore write frequency is bounded by movement, not time
- Geocoding results are cached in-memory (`GeocodingHelper._cache`) using a `lat/lng` key rounded to 4 decimal places, avoiding redundant reverse-geocoding calls for stationary users
- AI helper response target: within 5 seconds (`max_tokens: 1000` limits response size)
- OTP delivery uses a 15-second HTTP timeout (`http.post(...).timeout(Duration(seconds: 15))`)
- Connection and request state per `_FindTile` is cached per session to minimise Firestore reads on list scroll
---
 
### NFR2 — Security
 
- The Anthropic API key is loaded at runtime from a `.env` file via `flutter_dotenv` and is never hardcoded in source — the `.env` file is listed in `.gitignore`
- OTPs are stored server-side in Firestore with a 5-minute expiry (`expiresAt` field); expired documents are deleted after a failed match
- The `role` and `email` fields are locked post-registration — the `ProfileEditScreen` does not expose them for editing
- Location data, chat history, and voice calls are only accessible between mutually connected users, enforced in app logic via `ConnectionService.areMutuallyConnected`
**Firestore Security Rules (enforced server-side):**
 
| Collection | Rule |
|---|---|
| `/users/{uid}` | Any authenticated user can read; write only by owner UID |
| `/connections`, `/connection_requests` | Any authenticated user can read and write |
| `/email_otps/{doc}` | Public read/write (required for pre-auth OTP flow) |
| `/chats/{chatId}` | Read/write only if `request.auth.uid in resource.data.participants` |
| `/calls` + sub-collections | Any authenticated user |
 
---
 
### NFR3 — Battery Efficiency
 
- GPS uses `distanceFilter: 10` — zero Firestore writes occur when the user is stationary
- The `LocationService._subscription` is cancelled immediately on app pause/detach, preventing background GPS drain
---
 
### NFR4 — Reliability
 
- `lastLocation` fallback ensures offline users always appear on the map at their last known GPS fix
- WebRTC call state is monitored via a Firestore `snapshots()` listener; if the remote peer ends the call, the local `InAppCallScreen` pops itself automatically (`_hangUp(remote: true)`)
- AI suggestion fallback (`AiDecisionEngine._fallback()`) activates locally without any network dependency if the Claude API call fails or returns a non-200 response
---
 
### NFR5 — Multi-Role Support
 
Three user roles with role-specific behaviour throughout the app:
 
| Aspect | Student | Faculty | Others |
|---|---|---|---|
| Profile fields | `rollNumber`, `parentEmail` | `employeeId` | name + phone only |
| UI accent colour | Blue (`#1E3A8A`) | Purple (`#8B5CF6`) | Amber (`#F59E0B`) |
| Map marker colour | Blue | Purple | Amber |
| Role icon | `school_rounded` | `menu_book_rounded` | `people_rounded` |
 
---
 
### NFR6 — Platform Support
 
- **Primary platform:** Android (fully configured — `AndroidManifest.xml` declares `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `RECORD_AUDIO`, `BLUETOOTH`, `BLUETOOTH_CONNECT`, `INTERNET`)
- **iOS:** Project structure exists (`ios/` folder present, `GoogleService-Info.plist` slot exists) but `firebase_options.dart` throws `UnsupportedError` for iOS at runtime — iOS deployment is **not yet complete**
- **Flutter SDK:** `>=3.0.0 <4.0.0` (as declared in `pubspec.yaml`)
---


---

## 🔍 VerilogDistanceRanker — Proximity Classification

The `VerilogDistanceRanker` is a Dart class (named after the hardware concept of signal-range encoding) that classifies distances into 4 priority tiers using the `Geolocator.distanceBetween()` Haversine implementation:

| Tier | Range | Color | Meaning |
|------|-------|-------|---------|
| `nearest` | < 100 m | Green | Immediately reachable — highest priority |
| `close` | 100–500 m | Blue | Nearby — can arrive quickly |
| `moderate` | 500–2000 m | Amber | On campus — reachable within minutes |
| `far` | ≥ 2000 m | Red | Far away — last resort |

`VerilogDistanceRanker.rank()` takes a list of `CampusPerson` objects and a target `LatLng`, maps each to a `DistanceResult` with a computed distance and priority tier, and returns the list sorted ascending by distance. This ranked list feeds directly into the `AiDecisionEngine` for Claude API processing.

---

## 🌐 System Architecture

Campus Path Tracker is structured as a **four-layer mobile architecture** — Presentation, Application Logic, Data, and AI — each with clearly defined responsibilities and interfaces.

---

### Layer 1 — Presentation Layer (Flutter UI)

The Flutter frontend is organized into dedicated screens and tab widgets:

| Screen / Widget | Responsibility |
|-----------------|---------------|
| `SplashScreen` | Checks Firebase Auth session; routes to `AuthScreen` or `HomeScreen` |
| `AuthScreen` | Login and registration with EmailJS OTP flow; role selection (Student / Faculty / Others) |
| `HomeScreen` | App shell with AppBar; profile edit and logout actions |
| `PeopleScreen` | 3-tab container: **Nearby**, **Connections**, **Find People** |
| `_NearbyTab` | Live `flutter_map` with user markers, distance badges, and AI suggestion trigger |
| `_ConnectionsTab` | Real-time stream of mutual connections with online/offline status |
| `_FindPeopleTab` | Name-search across all campus users; send/cancel connection requests |
| `ProfileEditScreen` | Edit name, role, roll/employee ID, phone, parent contact |
| `ChatScreen` | In-app real-time text messaging via Firestore `/chats` |
| `CallScreen` | Peer-to-peer voice call UI using `flutter_webrtc` with mute/hang-up controls |
| `PersonLocationScreen` | Track a specific user's live or last-known location on a dedicated map |
| `IncomingCallListener` | Global overlay widget wrapping the Scaffold — pushes `CallScreen` on incoming ring |

All screens use `StatefulWidget` / `StreamBuilder` for reactive Firestore updates; `IncomingCallListener` uses `rootNavigator` to push across the full widget tree.

---

### Layer 2 — Application Logic Layer

| Module | Technology | Role |
|--------|------------|------|
| Authentication | Firebase Auth + EmailJS OTP | Verify identity before granting location access |
| Location Engine | `geolocator` + `geocoding` | Continuously poll GPS coordinates, convert to human-readable campus addresses |
| Proximity Engine | Cloud Firestore queries | Calculate distances between users using stored coordinates; filter by configurable radius (default: 100m) |
| Communication Module | `flutter_webrtc` + Firebase Firestore signaling | WebRTC peer connection for voice calls; offer/answer/ICE exchange via Firestore `/calls` collection |
| Chat Service | Firestore `/chats/{chatId}/messages` | Real-time messaging between connected users |
| Proximity Ranker | `VerilogDistanceRanker` (Dart) | Classifies distance into 4 tiers: Nearest (<100m), Close (<500m), Moderate (<2km), Far |
| AI Suggestion Engine | Claude API (Anthropic) via `http` | Receives top-5 ranked users; returns call/message action + ready-to-send message template |
| Permission Manager | `permission_handler` | Request and manage location, microphone, and camera permissions at runtime |

---

### Layer 3 — Data Layer (Firebase)

```
Firebase Project
├── Authentication
│   └── Email/password sessions — OTP verified via EmailJS before account creation
├── Cloud Firestore
│   ├── /users/{uid}
│   │   ├── firstName, lastName, role (Student|Faculty|Others)
│   │   ├── email, phone, rollNumber, employeeId
│   │   ├── location: GeoPoint         ← current position (updated on 10m movement)
│   │   ├── lastLocation: GeoPoint     ← last known position (fallback when offline)
│   │   ├── isOnline: bool
│   │   ├── lastSeen: Timestamp
│   │   └── accuracy, speed
│   ├── /connections/{uid_uid}
│   │   └── users: [uid1, uid2]        ← bidirectional mutual connection
│   ├── /connection_requests/{doc}
│   │   └── from, to, status           ← pending/accepted/rejected
│   ├── /email_otps/{doc}
│   │   └── otp, email, createdAt      ← public read/write (unauthenticated OTP flow)
│   ├── /chats/{chatId}
│   │   ├── participants: [uid1, uid2]
│   │   └── /messages/{msgId}          ← text, senderId, timestamp
│   └── /calls/{callId}
│       ├── offer, answer (SDP)        ← WebRTC signaling
│       ├── callerUid, calleeUid, status
│       ├── /callerCandidates/{c}      ← ICE candidates
│       └── /calleeCandidates/{c}
└── Security Rules
    ├── /users     → authenticated read (any user); write by owner UID only
    ├── /connections, /connection_requests → any authenticated user
    ├── /email_otps → public read/write (unauthenticated OTP delivery)
    ├── /chats     → participants only (checked via resource.data.participants)
    └── /calls + subcollections → any authenticated user
```

---

### Layer 4 — AI Decision Layer (Claude API)

The `AiDecisionEngine` class handles all AI interactions. It takes the top 5 nearby users ranked by `VerilogDistanceRanker` and sends them to the Claude API with role, distance, online status, and last-seen time. Claude returns a JSON array — no markdown — specifying `call` or `message` action, a one-sentence reason, and a ready-to-send message template for each candidate.

```
Input  →  top 5 users from VerilogDistanceRanker
          [ { name, role, distanceText, priority, status, last_seen }, ... ]

Prompt →  "For each person decide CALL or MESSAGE, give a one-sentence
           reason, and a short ready-to-send message template."

Output →  [ { uid, action, reason, messageTemplate }, ... ]
           rendered as swipeable suggestion cards on the Nearby tab
```

The call is made via `http.post` to `https://api.anthropic.com/v1/messages` using model `claude-sonnet-4-20250514`. The response JSON is parsed into `AiSuggestion` objects and displayed as actionable cards with direct call/message buttons.

---

### Full Data Flow

```text
User opens app
     |
     v
SplashScreen --> AuthScreen (EmailJS OTP + Firebase Auth login/register)
                      |
                      v
                 HomeScreen
                      |
                 PeopleScreen (3 tabs)
                /          |           \
           Nearby     Connections   Find People
             |
             v
     geolocator stream (10m distanceFilter)
     geocoding (lat/lng -> address)
             |
             v
     Firestore /users/{uid}
     { location, lastLocation, isOnline, lastSeen, accuracy, speed }
             |
             v
     VerilogDistanceRanker
     Haversine distance -> Nearest / Close / Moderate / Far
             |
             v
     _NearbyTab (flutter_map + OpenStreetMap)
     Live markers + distance badges
             |
        "Find Help" tapped
             |
             v
     AiDecisionEngine
     POST /v1/messages -> Claude API (claude-sonnet-4-20250514)
     Returns: [{ uid, action, reason, messageTemplate }]
             |
        User taps Call
             |
             v
     CallService (flutter_webrtc)
     Firestore /calls/{chatId} <-- WebRTC SDP + ICE signaling
     STUN: stun.l.google.com:19302
     Peer-to-peer audio established
             |
     IncomingCallListener (rootNavigator)
     Detects ringing -> pushes CallScreen on callee side
```

---

### Development Phases

| Phase | Scope | Status |
|-------|-------|--------|
| Phase 1 — Foundation | Firebase setup, Auth, EmailJS OTP, SplashScreen, AuthScreen | ✅ Complete |
| Phase 2 — Location | GPS tracking (`geolocator`), Firestore sync, lifecycle observer | ✅ Complete |
| Phase 3 — Proximity | `VerilogDistanceRanker`, Nearby tab, Map view, Person location screen | ✅ Complete |
| Phase 4 — Communication | In-app chat (`ChatService`), WebRTC calls (`CallService`), incoming call listener | ✅ Complete |
| Phase 5 — AI | `AiDecisionEngine` → Claude API, suggestion cards with action/reason/template | ✅ Complete |
| Phase 6 — Future | Indoor navigation, IoT wearables, offline mesh, ML movement prediction | 🔧 Planned |

---

## 🛠️ Technologies Used

| Technology | Purpose |
|------------|----------|
| Flutter | Frontend UI Development |
| Firebase Auth | Email/password authentication + session management |
| Cloud Firestore | Realtime database — users, connections, chats, calls, OTPs |
| EmailJS | OTP email delivery for registration verification |
| `geolocator` | GPS position stream with 10m distance filter |
| `geocoding` | Reverse geocoding — coordinates to human-readable address |
| `flutter_map` + OpenStreetMap + `latlong2` | Campus map rendering with live user markers |
| `flutter_webrtc` | WebRTC peer connection for voice calls |
| Claude API (Anthropic) — `claude-sonnet-4-20250514` | AI helper ranking with action + message template |
| `http` | REST calls to Anthropic `/v1/messages` endpoint |
| `permission_handler` | Runtime permission management (location, microphone) |
| `url_launcher` | External link handling (phone calls, URLs) |
| VS Code | Development Environment |

---

## 📍 User Journey

| Step | Action | Under the Hood |
|------|--------|----------------|
| 1 | User opens app → enters email | EmailJS dispatches OTP; Firebase Auth awaits verification |
| 2 | User enters OTP → verified | Firebase Auth session created; profile written to `/users/{uid}` |
| 3 | User sets profile (name, campus block) | Profile data stored in Firestore; location tracking begins |
| 4 | User moves 10+ metres | `geolocator` distance-filter fires; `geocoding` resolves address; Firestore updates `location`, `lastLocation`, `isOnline`, `lastSeen` |
| 5 | User opens Nearby tab | `_NearbyTab` renders `flutter_map`; Firestore stream pushes live marker updates |
| 6 | User taps "Find Help" | Nearby connected users queried; list sent to Claude API |
| 7 | Claude returns recommendation | Best helper card displayed with name, distance, one-tap call button |
| 8 | User initiates call | `CallService` creates WebRTC offer; Firestore `/calls` exchanges SDP + ICE; `flutter_webrtc` streams audio |

---

## 📡 Location Tracking Strategy

The system layers multiple positioning techniques for maximum accuracy:

| Source | Accuracy | Best For |
|--------|----------|----------|
| GPS (`geolocator`, `LocationAccuracy.high`) | 3–10 metres | Outdoor open spaces, grounds |
| Network/fused (OS-managed fallback) | 15–50 metres | Indoor buildings where GPS is weak |
| `lastLocation` (cached in Firestore) | Last known | Offline users — shown as last seen position |

Location updates are triggered by a **10-metre distance filter** rather than a fixed timer — this means no Firestore writes occur when the user is stationary, preserving battery life. The `lastSeen` timestamp and `isOnline` flag allow the proximity engine to surface `lastLocation` as a fallback for offline users, so they still appear on the map at their last known position.

---

## 🚀 Future Enhancements

---

### 1 — FCM Push Notifications for Incoming Calls ⚠️ Critical Gap

**What exists now:**
The `IncomingCallListener` widget in `lib/main.dart` listens to the Firestore `/calls` collection for documents where `calleeUid == myUid` and `status == 'ringing'`. This works **only when the app is open and in the foreground**. If the callee's screen is off or the app is backgrounded, the Firestore listener is paused — the call is missed entirely. For a campus safety app, this is the single most critical limitation.

**What needs to be added:**
- Add `firebase_messaging` to `pubspec.yaml`
- Register a background message handler via `FirebaseMessaging.onBackgroundMessage()`
- When `CallService.startCall()` writes a `ringing` document to Firestore, trigger a Cloud Function to send a high-priority FCM notification to the callee's device token
- Store the FCM token on login: `users/{uid}.fcmToken`
- Handle the notification tap to deep-link directly into `CallScreen`

**Enabling technology:** `firebase_messaging` package + Firebase Cloud Functions

---

### 2 — Video Calls via `flutter_webrtc`

**What exists now:**
`CallService` in `lib/main.dart` already manages a complete WebRTC peer connection lifecycle — SDP offer/answer exchange, ICE candidate negotiation via Firestore `/calls/{chatId}`, STUN server config (`stun.l.google.com:19302`), mute toggle, and remote hang-up detection. The `_getLocalAudio()` method calls `navigator.mediaDevices.getUserMedia({'audio': true, 'video': false})` — video is explicitly set to `false`.

**What needs to be added:**
- Change `'video': false` → `'video': true` in `_getLocalAudio()`
- Add `Permission.camera.request()` alongside the existing `Permission.microphone.request()` call
- Add `RTCVideoRenderer` widgets inside `InAppCallScreen` for local and remote video preview
- Add `<uses-permission android:name="android.permission.CAMERA"/>` to `AndroidManifest.xml`

**Enabling technology:** `flutter_webrtc` (already in `pubspec.yaml`) — no new package required

---

### 3 — Emergency SOS Broadcast

**What exists now:**
`ConnectionService.getConnectedUids(myUid)` fetches all mutual connection UIDs from the Firestore `/connections` collection. The `AiDecisionEngine` already builds a ranked list of nearby connected users with distance and role. The Firestore infrastructure to write to named collections and address a known list of UIDs is fully operational.

**What needs to be added:**
- Add a dedicated SOS button on `HomeScreen` or `_NearbyTab`
- On tap, write an SOS document to a new `/sos_alerts` collection: `{ fromUid, location: GeoPoint, timestamp, message: "I need help" }`
- Use FCM (item 1 above) to push a high-priority notification to all `getConnectedUids()` simultaneously
- Each recipient sees the sender's last known `GeoPoint` from `users/{uid}.location` pinned on their map

**Enabling technology:** Existing `ConnectionService` + `/connections` Firestore collection + `firebase_messaging`

---

### 4 — Turn-by-Turn Route Guidance on the Map

**What exists now:**
`_NearbyTab` renders a live `flutter_map` + OpenStreetMap map with a `MarkerLayer` showing all nearby users. The `LatLng` coordinates of every user are already computed from their Firestore `location` GeoPoint. The map and HTTP infrastructure are both fully wired.

**What needs to be added:**
- When a user taps a person's marker or the "Navigate" action from `AiDecisionEngine` suggestion cards, call the OSRM public routing API: `http://router.project-osrm.org/route/v1/foot/{fromLng},{fromLat};{toLng},{toLat}?geometries=geojson`
- Parse the returned GeoJSON polyline coordinates into a `List<LatLng>`
- Render it using `flutter_map`'s `PolylineLayer` on the existing `FlutterMap` widget

**Enabling technology:** `flutter_map` polyline layer (already imported) + OSRM public API (no key required) + `http` package (already in `pubspec.yaml`)

---

### 5 — Location History Timeline

**What exists now:**
Every GPS update in `LocationService.startTracking(uid)` writes `location` and `lastLocation` GeoPoints plus a `lastSeen` server timestamp to `users/{uid}`. The stream fires on every 10-metre movement but overwrites the same document rather than appending — so movement history is lost.

**What needs to be added:**
- In `LocationService.startTracking()`, alongside the existing `users/{uid}` update, add a secondary write to a subcollection: `users/{uid}/location_history/{timestamp}` with `{ location: GeoPoint, ts: serverTimestamp, accuracy, speed }`
- Build a `TimelineView` screen that reads this subcollection ordered by `ts` and replays the user's path as an animated polyline on `flutter_map`
- Useful for faculty tracking student movement during campus events or post-incident route reconstruction

**Enabling technology:** Existing `geolocator` stream + one additional Firestore subcollection write in `LocationService` + `flutter_map` polyline layer

---

### 6 — iOS Full Support

**What exists now:**
The `ios/` folder structure is present in the project. `firebase_options.dart` contains the `DefaultFirebaseOptions.currentPlatform` switch but throws `UnsupportedError` for the iOS platform case. All Flutter/Dart logic in `lib/main.dart` is platform-agnostic and requires no changes.

**What needs to be added:**
- Configure `GoogleService-Info.plist` with Firebase iOS app credentials and add it to `ios/Runner/`
- Fix the `UnsupportedError` iOS branch in `firebase_options.dart`
- Add `CallKit` and `PushKit` entitlements for background VoIP call reception (required for WebRTC calls to wake the app on iOS)
- Add iOS-specific permission strings (`NSLocationWhenInUseUsageDescription`, `NSMicrophoneUsageDescription`) to `Info.plist`

**Enabling technology:** Apple Developer account + Firebase iOS SDK + CallKit/PushKit frameworks

---

### Development Roadmap

| # | Enhancement | Complexity | Existing Leverage |
|---|-------------|------------|-------------------|
| 1 | FCM Push Notifications | Medium | Firebase project already live; `IncomingCallListener` logic reused |
| 2 | Video Calls | Low | `flutter_webrtc` already integrated — one flag change + renderer widget |
| 3 | Emergency SOS | Low | `ConnectionService.getConnectedUids()` + Firestore already wired |
| 4 | Route Guidance | Low | `flutter_map` + `http` already in project; OSRM needs no API key |
| 5 | Location Timeline | Low | `LocationService` stream already fires on every 10m move |
| 6 | iOS Full Support | High | Folder structure exists; needs Apple Developer account |

## 🎓 Project Information

**Project Title:** Campus Path Tracker

**Developed For:** Project Space 2026 Season 8
Powered by Technical Hub — Aditya University

---

## 🌟 Vision

> "Building a smarter and safer campus through AI-powered real-time proximity awareness."

---

## 🤝 Contributors

- Team NearNet Crew
- Project Space Season 8 Participants

---

## 📬 Contact

Feel free to contribute, collaborate, and improve the project 🚀
