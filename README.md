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


### FR1 — User Registration with EmailJS OTP Verification + Firebase Auth
- User selects a role (Student / Faculty / Others) and enters email + password
- A 6-digit OTP is generated and sent via **EmailJS** (`api.emailjs.com/v1.0/email/send`) to the entered email
- OTP is stored in Firestore `email_otps/{email}` with `createdAt` and `expiresAt` (5-minute TTL); expired OTPs are auto-deleted
- Registration is blocked until OTP is verified (matched against in-memory value or Firestore fallback)
- After OTP verification, account is created via `FirebaseAuth.createUserWithEmailAndPassword` and profile is written to Firestore `users/{uid}`
- Role-specific profile fields: Students store `rollNumber` + `parentEmail`; Faculty stores `employeeId`; all roles store `firstName`, `lastName`, `phone`, `email`, `role`
- Login via `FirebaseAuth.signInWithEmailAndPassword`
- Password reset via Firebase `sendPasswordResetEmail` (dialog captures email, sends reset link)
- Logout marks user offline in Firestore, stops GPS tracking, then calls `FirebaseAuth.signOut()`

---

### FR2 — Real-Time GPS Tracking with 10m Distance Filter and Firestore Sync
- Authenticated user's location is tracked continuously using `Geolocator.getPositionStream` with `distanceFilter: 10` (metres) and `LocationAccuracy.high`
- On every position update, the following fields are written to `users/{uid}`: `location` (GeoPoint), `lastLocation` (GeoPoint), `isOnline: true`, `lastSeen` (server timestamp), `accuracy` (metres), `speed` (m/s)
- Tracking starts on app resume and stops on app pause/detach via `AppLifecycleObserver`
- No Firestore writes occur when the device is stationary — the distance filter prevents idle writes, conserving battery

---

### FR3 — Nearby User Detection with 4-Tier Proximity Classification and Interactive Map
- All campus users within 2000m are detected and classified using `Geolocator.distanceBetween` via `VerilogDistanceRanker`:
  - **Nearest** — < 100 m
  - **Close** — 100–499 m
  - **Moderate** — 500–1999 m
  - **Far** — ≥ 2000 m
- Each tier is displayed with a distinct colour badge
- The Nearby tab renders an interactive **OpenStreetMap tile map** (via `flutter_map`) with role-coloured, initialled markers for all users
- Marker colours: green = self, blue = student, purple = faculty, amber = others, grey = offline
- Tapping a marker shows a dialog with the user's name, role, online status, last-seen time, and reverse-geocoded place name (cached via `GeocodingHelper`)
- A scrollable ranked list below the map shows distance text, proximity badge, and online/offline indicator per user

---

### FR4 — Bidirectional Connection Management with Real-Time Notifications
- Any user can send a connection request; this writes to the `connection_requests` collection with `fromUid`, `fromName`, `toUid`, `toName`, `status: 'pending'`, `createdAt`
- A real-time notification bell badge on the PeopleScreen app bar shows the count of pending incoming requests via Firestore stream
- A bottom-sheet notifications panel lists all pending requests with Accept and Decline buttons
- Accepting creates a symmetric `connections/{fromUid}_{toUid}` document containing a `users` array and `createdAt`; declining updates `status` to `'rejected'`
- Location viewing, in-app chat, and voice calls are gated behind mutual connection (`ConnectionService.areMutuallyConnected` check); non-connected users see a "Location Access Restricted" screen

---

### FR5 — Campus-Wide User Search with Connection Status and Distance Display
- The Find People tab provides live search across all registered campus users via a real-time Firestore `users` stream
- Search filters by `fullName`, `role`, `rollNumber`, and `email` (case-insensitive)
- Each result tile shows: name, role, roll number, online/offline dot indicator, and last-seen time
- If the user is already connected: distance in metres/km and a "View Location" button are shown
- If not connected: a "Connect" button is shown; after tapping it changes to "Requested" (orange chip)
- Connection and request state is cached per session to minimise Firestore reads

---

### FR6 — AI-Powered Helper Recommendation via Claude API
- On the Person Location screen, the app calls the Anthropic API (`claude-sonnet-4-20250514`, `max_tokens: 1000`) with a prompt containing up to 5 nearby connected users ranked by proximity
- Each user's context includes: name, role, distance (text), proximity tier, online status, and last-seen time
- The API returns a JSON array of objects, each with `uid`, `action` (CALL or MESSAGE), `reason` (one sentence), and `messageTemplate` (ready-to-send text)
- AI suggestion cards display: recommended action, target person's name + reverse-geocoded location, Claude's reason, the message template, and a live action button that opens the in-app call or chat screen
- A local heuristic fallback (online → CALL, offline → MESSAGE) activates automatically if the API call fails

---

### FR7 — Peer-to-Peer Voice Calls via flutter_webrtc and Firestore Signalling
- In-app audio calls are established using `flutter_webrtc` with the following Firestore signalling flow at `calls/{chatId}`:
  1. Caller captures audio (`getUserMedia {audio: true}`), creates SDP offer, writes offer + `callerUid`, `calleeUid`, `status: 'ringing'` to the call document
  2. Callee creates SDP answer, writes it to the call document, updating `status: 'active'`
  3. ICE candidates are exchanged in real time via `callerCandidates` and `calleeCandidates` sub-collections
  4. Either party hangs up: peer connection is closed, media stream is disposed, `status` is set to `'ended'`
- STUN servers used: `stun.l.google.com:19302` and `stun1.l.google.com:19302`
- The call screen shows caller/callee name and role, a live call duration timer, a mute toggle, and a hang-up button

---

### FR8 — Real-Time In-App Text Chat with Read Receipts and Unread Badges
- Messages are stored at `chats/{chatId}/messages` where `chatId` is the lexicographically sorted UID pair (`uid1_uid2`)
- Each message document stores: `from` (uid), `text`, `ts` (server timestamp), `read` (bool)
- Messages stream in real time ordered by `ts` ascending; the chat screen auto-scrolls to the latest message on update
- Sent messages are displayed right-aligned (primary blue); received messages are displayed left-aligned (white); timestamps are shown per bubble
- On opening a chat, all unread messages from the peer are batch-marked `read: true` via a Firestore batch commit
- The Connections tab displays a live unread message badge count per contact via a Firestore stream filtered by `from == peerUid` and `read == false`
- The parent `chats/{chatId}` document is updated with `lastMessage`, `lastTs`, and `lastFrom` on every send

---

### FR9 — Global Incoming Call Listener with Root-Navigator Overlay
- `IncomingCallListener` wraps the entire home Scaffold and subscribes to the Firestore `calls` collection filtered by `calleeUid == currentUser.uid` and `status == 'ringing'`
- On detecting an incoming call, an `AlertDialog` is shown using `Navigator.of(context, rootNavigator: true)` so it appears above all routes and navigation stacks
- The dialog displays the caller's name, role, and initials avatar with Accept and Decline buttons
- Accepting navigates to `InAppCallScreen` (isOutgoing: false) via `rootNavigator: true`
- Declining updates the call document `status` to `'ended'`

---

### FR10 — App Lifecycle Observer with Automatic Online/Offline Management
- `AppLifecycleObserver extends WidgetsBindingObserver` is registered on home screen init
- On `AppLifecycleState.resumed`: GPS tracking restarts via `LocationService.startTracking(uid)`
- On `AppLifecycleState.paused` or `AppLifecycleState.detached`: GPS tracking stops and Firestore `users/{uid}` is updated with `isOnline: false` and `lastSeen` (server timestamp)
- The same offline update is triggered explicitly on logout
- Offline users remain visible on the map at their last known position via the `displayLocation` getter (`lastLocation ?? location`)

---

## Non-Functional Requirements

### NFR1 — Performance
- Location updates fire only on ≥ 10m movement (distance-filter stream, not polling timer), ensuring Firestore write frequency is bounded by physical movement
- AI helper response target: within 5 seconds (Claude API with `max_tokens: 1000`)
- OTP send timeout: 15 seconds (`http.post` with `.timeout(Duration(seconds: 15))`)
- Geocoding results are cached in-memory (`GeocodingHelper._cache`) to avoid redundant reverse-geocoding calls

### NFR2 — Security
- Anthropic API key is loaded from a `.env` file via `flutter_dotenv` and never hardcoded
- OTP is stored server-side in Firestore `email_otps` with a 5-minute expiry; expired documents are deleted after failed verification
- Role and email fields are locked post-registration (UI enforced — edit screen shows a warning and does not expose those fields)
- Location and chat data are only accessible between mutually connected users (enforced in app logic via `ConnectionService.areMutuallyConnected`)

### NFR3 — Battery Efficiency
- GPS uses a distance-filter stream (`distanceFilter: 10`) instead of a time-based polling timer
- Firestore location writes occur only when the user physically moves ≥ 10 metres — zero writes when stationary

### NFR4 — Reliability
- `lastLocation` fallback ensures offline users still appear on the map at their last known GPS position (`displayLocation` returns `lastLocation ?? location` for offline users)
- WebRTC call state is monitored via a Firestore snapshot listener; if the remote peer ends the call, the local call screen is dismissed automatically
- AI suggestion fallback activates locally without any network dependency if the Claude API call fails or times out

### NFR5 — Multi-Role Support
- Three user roles (Student, Faculty, Others) with role-specific Firestore profile fields, role-coloured UI accents, and role-aware map markers throughout the application

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

| Enhancement | What Exists Now | What Needs to Be Added | Enabling Technology |
| :--- | :--- | :--- | :--- |
| **Video Calls** | `flutter_webrtc` is integrated; `CallService._getLocalAudio` has `video: false` | Change `video: false` → `video: true`; add camera permission; add `RTCVideoRenderer` widget in `CallScreen` | `flutter_webrtc` (in pubspec), `CAMERA` permission in AndroidManifest |
| **Route Guidance** | `flutter_map` + OpenStreetMap + `latlong2` are live on the Nearby tab with user markers | Add OSRM API call between two `LatLng` points; draw a `PolylineLayer` on the existing map | `flutter_map` polyline layer, OSRM public routing API |
| **Push Notifications** | FCM is not yet integrated; Firebase project exists | Add `firebase_messaging` to pubspec; register background handler; store FCM tokens in `/users/{uid}` | `firebase_messaging` package, AndroidManifest background service |
| **Emergency SOS** | Firestore `/connections` list and broadcast structure exist | Add an SOS document to a new `/sos_alerts` collection; trigger FCM notification to all connected UIDs | Existing Firestore connections + `firebase_messaging` |
| **Indoor Navigation** | `LocationService` uses GPS-only with no provider interface | Refactor `LocationService` into abstract `LocationProvider` with BLE subclass; integrate `flutter_blue_plus` | `flutter_blue_plus`, BLE beacon hardware |
| **iOS Full Support** | iOS folder exists; `firebase_options.dart` throws `UnsupportedError` for iOS | Configure `GoogleService-Info.plist`; add CallKit/PushKit entitlements; fix Firebase config | Apple Developer account, CallKit, PushKit |
| **Location Timeline** | `lastLocation` GeoPoint and `lastSeen` Timestamp stored in Firestore | Add a `/location_history/{uid}/snapshots` subcollection; build a `TimelineView` for map replay | Existing `geolocator` stream + Firestore subcollection |

---

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
