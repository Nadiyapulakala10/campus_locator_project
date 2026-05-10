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

### FR-01 · User Registration & Authentication
- Users register with name, campus block, and email address
- A one-time password (OTP) is dispatched via **EmailJS** to verify the email before account creation
- On successful OTP entry, a Firebase Auth session is created and the user profile is written to Firestore under `/users/{uid}`
- Subsequent logins reuse the active Firebase session; OTP re-verification is triggered on session expiry
- **Acceptance criteria:** A new user can register, receive OTP, verify, and reach `HomeScreen` within 60 seconds; profile written to Firestore `/users/{uid}`

### FR-02 · Real-Time Location Tracking
- On first launch (post-login), the app requests `ACCESS_FINE_LOCATION` and `ACCESS_BACKGROUND_LOCATION` via `permission_handler`
- The `geolocator` package streams GPS using a **10-metre distance filter** (not a timer) — updates fire only when the user moves 10m, saving battery. Both `location` (current) and `lastLocation` (fallback) GeoPoints are written to Firestore
- `geocoding` converts raw coordinates into a human-readable campus address (block / building level)
- The `_NearbyTab` map (powered by `flutter_map` + OpenStreetMap tiles + `latlong2`) renders live user markers updating in real time via Firestore stream
- **Acceptance criteria:** Location updates reflect on the map within 15 seconds of a user moving

### FR-03 · Nearby User Detection
- The proximity engine queries Firestore for all users whose stored coordinates fall within a configurable radius (default: **100 metres**), calculated using the Haversine formula
- Results are filtered to **trusted connections only** — users present in `/connections/{uid}/list`
- `VerilogDistanceRanker.rank()` applies the Haversine formula and classifies each result: **Nearest** (<100m, green), **Close** (<500m, blue), **Moderate** (<2km, amber), **Far** (≥2km, red)
- The `_NearbyTab` displays each match as a map marker with name label, priority badge, and distance text
- **Acceptance criteria:** At least 3 nearby users (within 100m) appear on the map within 5 seconds of opening `_NearbyTab`

### FR-04 · Friend Search
- `_FindPeopleTab` exposes a name-based search field that queries the `/users` Firestore collection using prefix matching
- Results display name, role, last-seen timestamp, and distance (if location available)
- Users can send a connection request from the result card; the request is written to `/connection_requests`; recipients see it in `_ConnectionsTab`
- **Acceptance criteria:** A search query returns results within 2 seconds; a connection request is visible to the recipient on their Connections tab

### FR-05 · Connections Management
- `_ConnectionsTab` streams `/connections` where `users arrayContains myUid`, resolving each peer UID to a full `CampusPerson` profile in real time
- Users can add (via search), remove, or block connections
- Connections are bidirectional — both users must accept before location sharing is activated
- **Acceptance criteria:** Adding a connection and having the peer accept results in both users appearing on each other's `_NearbyTab`

### FR-06 · AI-Powered Helper Recommendation
- When a user triggers "Find Help", the app collects the top nearby connected users with name, distance, and connection status
- A structured prompt is sent to the **Claude API (Anthropic)** via `http` REST call to `/v1/messages`
- Claude ranks candidates by proximity and trust level and returns a natural-language recommendation
- The result is displayed as an action card on `_NearbyTab` with a one-tap call/message button
- **Acceptance criteria:** AI recommendation returns and renders within 5 seconds of trigger; recommended user is the closest active connection

### FR-07 · Voice Calls (WebRTC)
- `CallService.startCall()` creates an RTCPeerConnection, captures local audio via `flutter_webrtc`, and writes the WebRTC offer SDP to Firestore `/calls/{chatId}`
- ICE candidates are exchanged via Firestore subcollections (`/callerCandidates`, `/calleeCandidates`) using STUN servers (`stun.l.google.com:19302`)
- The callee's `IncomingCallListener` detects the ringing state via Firestore stream and pushes `CallScreen` using `rootNavigator`
- `CallService.answerCall()` reads the offer, creates an answer SDP, and completes the WebRTC handshake
- `CallService.hangUp()` closes the peer connection, disposes the media stream, and marks the call `ended` in Firestore
- `CallService.toggleMute()` enables/disables the local audio track without dropping the call
- The `RECORD_AUDIO` permission is declared in AndroidManifest; `BLUETOOTH`/`BLUETOOTH_CONNECT` permissions enable headset routing
- **Acceptance criteria:** Caller and callee establish a two-way audio connection; mute and hang-up controls work; call status transitions idle → ringing → active → ended

### FR-08 · Firebase Security & Data Integrity
- `/users/{uid}` — read and write restricted to the authenticated owner UID only
- `/connections` — read and write open to any authenticated user (required for mutual connection requests)
- `/email_otps/{doc}` — public read/write (required for unauthenticated OTP verification flow before Firebase Auth session exists)
- All rules enforced server-side via Firestore Security Rules — client cannot bypass them
- **Acceptance criteria:** An unauthenticated request to `/users` write path returns `PERMISSION_DENIED`; chat read is blocked unless `request.auth.uid in resource.data.participants`

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

- Indoor Navigation & Route Guidance
- Voice Alerts
- Emergency SOS System
- Battery status of people
- Disconnect option for users
- student can have direct access to see faculty location
- Faculty can have option to turn on / turn off their location
- call and message feature can be implemented in a better way for user experince

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
