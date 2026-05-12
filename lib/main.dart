// Campus Locator — COMPLETE VERSION (ALL BUGS FIXED)
// Fixes applied:
// 1. Claude model identifier loaded from .env (was hardcoded wrong string)
// 2. EmailJS credentials loaded from .env (were hardcoded in source)
// 3. IncomingCallListener tracks callDocId instead of boolean flag
// 4. CallService closes existing PC before creating a new one (static state conflict)
// 5. Microphone permission checked via permission_handler before getUserMedia
// 6. IncomingCallListener wraps entire Scaffold (not FutureBuilder body)
// 7. Navigator.of(context, rootNavigator: true) used in IncomingCallListener
// 8. forgotPassword context captured before async gap

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ─────────────────────────────────────────
//  CONFIGS
// ─────────────────────────────────────────

// FIX 2: EmailJS credentials now loaded from .env instead of hardcoded
class EmailJSConfig {
  static String get serviceId => dotenv.env['EMAILJS_SERVICE_ID'] ?? '';
  static String get templateId => dotenv.env['EMAILJS_TEMPLATE_ID'] ?? '';
  static String get publicKey => dotenv.env['EMAILJS_PUBLIC_KEY'] ?? '';
}

// FIX 1: Claude model identifier now loaded from .env
// Add to your .env:
//   ANTHROPIC_API_KEY=your_key_here
//   ANTHROPIC_MODEL=claude-sonnet-4-5
class AnthropicConfig {
  static String get apiKey => dotenv.env['ANTHROPIC_API_KEY'] ?? '';
  static String get model =>
      dotenv.env['ANTHROPIC_MODEL'] ?? 'claude-sonnet-4-5';
}

// ─────────────────────────────────────────
//  MAIN
// ─────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CampusLocatorApp());
}

// ─────────────────────────────────────────
//  COLORS
// ─────────────────────────────────────────
class AppColors {
  static const Color primary = Color(0xFF1E3A8A);
  static const Color accent = Color(0xFF10B981);
  static const Color facultyAccent = Color(0xFF8B5CF6);
  static const Color othersAccent = Color(0xFFF59E0B);
  static const Color background = Color(0xFFF3F4F6);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color white = Colors.white;
  static const Color purple = Color(0xFF8B5CF6);
  static const Color warning = Color(0xFFF59E0B);
  static const Color offlineGrey = Color(0xFF9CA3AF);
}

// ─────────────────────────────────────────
//  LAST SEEN HELPER
// ─────────────────────────────────────────
class LastSeenHelper {
  static String format(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─────────────────────────────────────────
//  GEOCODING HELPER
// ─────────────────────────────────────────
class GeocodingHelper {
  static final Map<String, String> _cache = {};

  static Future<String> getPlaceName(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
    if (_cache.containsKey(key)) return _cache[key]!;
    try {
      final placemarks = await placemarkFromCoordinates(
        lat,
        lng,
      ).timeout(const Duration(seconds: 5));
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if (p.name != null && p.name!.isNotEmpty && p.name != p.street) {
          parts.add(p.name!);
        }
        if (p.street != null && p.street!.isNotEmpty) parts.add(p.street!);
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          parts.add(p.subLocality!);
        } else if (p.locality != null && p.locality!.isNotEmpty) {
          parts.add(p.locality!);
        }
        final result = parts.isNotEmpty
            ? parts.take(2).join(', ')
            : '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        _cache[key] = result;
        return result;
      }
    } catch (_) {}
    final fallback = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    _cache[key] = fallback;
    return fallback;
  }
}

// ─────────────────────────────────────────
//  CONTACT HELPER
// ─────────────────────────────────────────
class ContactHelper {
  static Future<void> makeCall(BuildContext context, String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      _showNoPhone(context);
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showNoPhone(context);
    }
  }

  static Future<void> sendSMS(
    BuildContext context,
    String? phone, {
    String message = '',
  }) async {
    if (phone == null || phone.trim().isEmpty) {
      _showNoPhone(context);
      return;
    }
    final uri = Uri(
      scheme: 'sms',
      path: phone.trim(),
      queryParameters: message.isNotEmpty ? {'body': message} : null,
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showNoPhone(context);
    }
  }

  static void _showNoPhone(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.info_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('No phone number saved for this person.')),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  LOCATION SERVICE
// ─────────────────────────────────────────
class LocationService {
  static StreamSubscription<Position>? _subscription;

  static Future<Position?> getPermissionAndPosition() async {
    bool svc = await Geolocator.isLocationServiceEnabled();
    if (!svc) return null;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  static void startTracking(String uid) {
    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'lastLocation': GeoPoint(pos.latitude, pos.longitude),
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'accuracy': pos.accuracy,
        'speed': pos.speed,
      });
    });
  }

  static void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<void> goOffline(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}

// ─────────────────────────────────────────
//  LIFECYCLE OBSERVER
// ─────────────────────────────────────────
class AppLifecycleObserver extends WidgetsBindingObserver {
  final String uid;
  AppLifecycleObserver(this.uid);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        LocationService.startTracking(uid);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        LocationService.stopTracking();
        LocationService.goOffline(uid);
        break;
      default:
        break;
    }
  }
}

// ─────────────────────────────────────────
//  CONNECTION SERVICE
// ─────────────────────────────────────────
class ConnectionService {
  static Future<bool> areMutuallyConnected(
    String myUid,
    String otherUid,
  ) async {
    final q1 = await FirebaseFirestore.instance
        .collection('connections')
        .doc('${myUid}_$otherUid')
        .get();
    final q2 = await FirebaseFirestore.instance
        .collection('connections')
        .doc('${otherUid}_$myUid')
        .get();
    return q1.exists || q2.exists;
  }

  static Future<List<String>> getConnectedUids(String myUid) async {
    final snap = await FirebaseFirestore.instance
        .collection('connections')
        .where('users', arrayContains: myUid)
        .get();
    final uids = <String>[];
    for (final doc in snap.docs) {
      final users = List<String>.from(doc['users']);
      final other = users.firstWhere((u) => u != myUid, orElse: () => '');
      if (other.isNotEmpty) uids.add(other);
    }
    return uids;
  }
}

// ─────────────────────────────────────────
//  CHAT SERVICE
// ─────────────────────────────────────────
class ChatService {
  static String chatId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  static CollectionReference<Map<String, dynamic>> messagesRef(
    String myUid,
    String otherUid,
  ) {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId(myUid, otherUid))
        .collection('messages');
  }

  static Future<void> sendMessage({
    required String myUid,
    required String otherUid,
    required String text,
  }) async {
    await messagesRef(myUid, otherUid).add({
      'from': myUid,
      'text': text.trim(),
      'ts': FieldValue.serverTimestamp(),
      'read': false,
    });
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId(myUid, otherUid))
        .set({
      'participants': [myUid, otherUid],
      'lastMessage': text.trim(),
      'lastTs': FieldValue.serverTimestamp(),
      'lastFrom': myUid,
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> messageStream(
    String myUid,
    String otherUid,
  ) {
    return messagesRef(
      myUid,
      otherUid,
    ).orderBy('ts', descending: false).snapshots();
  }

  static Future<void> markRead(String myUid, String otherUid) async {
    final snap = await messagesRef(
      myUid,
      otherUid,
    ).where('from', isEqualTo: otherUid).where('read', isEqualTo: false).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  static Stream<int> unreadStream(String myUid, String otherUid) {
    return messagesRef(myUid, otherUid)
        .where('from', isEqualTo: otherUid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }
}

// ─────────────────────────────────────────
//  WEBRTC CALL SERVICE
//  FIX 4: Close existing PC before creating a new one to prevent
//  static state conflict when concurrent calls overlap.
//  FIX 5: Check microphone permission before getUserMedia.
// ─────────────────────────────────────────
class CallService {
  static RTCPeerConnection? _pc;
  static MediaStream? _localStream;

  static final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  // FIX 5: Request microphone permission before calling getUserMedia
  static Future<MediaStream> _getLocalAudio() async {
    final status = await Permission.microphone.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      throw Exception(
        'Microphone permission denied. Please allow microphone access in settings.',
      );
    }
    return await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
  }

  // FIX 4: Helper to safely tear down any existing connection
  static Future<void> _closeExisting() async {
    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }
    if (_localStream != null) {
      await _localStream!.dispose();
      _localStream = null;
    }
  }

  static Future<RTCPeerConnection> _createPc(
    void Function(RTCIceCandidate) onIce,
  ) async {
    final pc = await createPeerConnection(_iceConfig);
    pc.onIceCandidate = (c) {
      if (c.candidate != null) onIce(c);
    };
    return pc;
  }

  static Future<void> startCall(String myUid, String peerUid) async {
    // FIX 4: Always close existing before starting new
    await _closeExisting();

    final ref = FirebaseFirestore.instance
        .collection('calls')
        .doc(ChatService.chatId(myUid, peerUid));

    _localStream = await _getLocalAudio();
    _pc = await _createPc((c) async {
      await ref.collection('callerCandidates').add({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    });

    for (final t in _localStream!.getTracks()) {
      _pc!.addTrack(t, _localStream!);
    }

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await ref.set({
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'callerUid': myUid,
      'calleeUid': peerUid,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
    });

    ref.snapshots().listen((snap) async {
      final data = snap.data();
      if (data?['answer'] != null &&
          _pc?.signalingState != RTCSignalingState.RTCSignalingStateStable) {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(data!['answer']['sdp'], data['answer']['type']),
        );
      }
    });

    ref.collection('calleeCandidates').snapshots().listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final d = ch.doc.data()!;
          _pc!.addCandidate(
            RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']),
          );
        }
      }
    });
  }

  static Future<void> answerCall(String myUid, String callerUid) async {
    // FIX 4: Always close existing before answering
    await _closeExisting();

    final ref = FirebaseFirestore.instance
        .collection('calls')
        .doc(ChatService.chatId(callerUid, myUid));

    _localStream = await _getLocalAudio();
    _pc = await _createPc((c) async {
      await ref.collection('calleeCandidates').add({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    });

    for (final t in _localStream!.getTracks()) {
      _pc!.addTrack(t, _localStream!);
    }

    final callData = (await ref.get()).data()!;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(
        callData['offer']['sdp'],
        callData['offer']['type'],
      ),
    );

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    await ref.update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'status': 'active',
    });

    ref.collection('callerCandidates').snapshots().listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final d = ch.doc.data()!;
          _pc!.addCandidate(
            RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']),
          );
        }
      }
    });
  }

  static Future<void> hangUp(String myUid, String peerUid) async {
    await _pc?.close();
    _pc = null;
    await _localStream?.dispose();
    _localStream = null;
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(ChatService.chatId(myUid, peerUid))
          .update({'status': 'ended'});
    } catch (_) {}
  }

  static void toggleMute(bool muted) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }
}

// ─────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────
enum ContactPriority { nearest, close, moderate, far }

class CampusPerson {
  final String uid, firstName, lastName, role, email;
  final String? rollNumber, employeeId, phone;
  final GeoPoint? location, lastLocation;
  final bool isOnline;
  final DateTime? lastSeen;

  CampusPerson({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.email,
    this.rollNumber,
    this.employeeId,
    this.phone,
    this.location,
    this.lastLocation,
    this.isOnline = false,
    this.lastSeen,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l';
  }

  Color get roleColor {
    switch (role) {
      case 'Faculty':
        return AppColors.purple;
      case 'Others':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  GeoPoint? get displayLocation =>
      isOnline ? location : (lastLocation ?? location);

  factory CampusPerson.fromFirestore(String uid, Map<String, dynamic> data) {
    return CampusPerson(
      uid: uid,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      role: data['role'] ?? 'Student',
      email: data['email'] ?? '',
      rollNumber: data['rollNumber'],
      employeeId: data['employeeId'],
      phone: data['phone'],
      location: data['location'] as GeoPoint?,
      lastLocation: data['lastLocation'] as GeoPoint?,
      isOnline: data['isOnline'] ?? false,
      lastSeen: data['lastSeen'] != null
          ? (data['lastSeen'] as Timestamp).toDate()
          : null,
    );
  }
}

class DistanceResult {
  final CampusPerson person;
  final double distanceMeters;
  final ContactPriority priority;
  final String priorityLabel;

  DistanceResult({
    required this.person,
    required this.distanceMeters,
    required this.priority,
    required this.priorityLabel,
  });

  String get distanceText => distanceMeters < 1000
      ? '${distanceMeters.toStringAsFixed(0)} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';
}

class AiSuggestion {
  final String action, reason, messageTemplate;
  final DistanceResult target;
  AiSuggestion({
    required this.action,
    required this.reason,
    required this.messageTemplate,
    required this.target,
  });
}

// ─────────────────────────────────────────
//  VERILOG RANKER
// ─────────────────────────────────────────
class VerilogDistanceRanker {
  static ContactPriority encode(double d) {
    if (d < 100) return ContactPriority.nearest;
    if (d < 500) return ContactPriority.close;
    if (d < 2000) return ContactPriority.moderate;
    return ContactPriority.far;
  }

  static String priorityLabel(ContactPriority p) {
    switch (p) {
      case ContactPriority.nearest:
        return 'Nearest';
      case ContactPriority.close:
        return 'Close';
      case ContactPriority.moderate:
        return 'Moderate';
      case ContactPriority.far:
        return 'Far';
    }
  }

  static Color priorityColor(ContactPriority p) {
    switch (p) {
      case ContactPriority.nearest:
        return AppColors.accent;
      case ContactPriority.close:
        return const Color(0xFF3B82F6);
      case ContactPriority.moderate:
        return AppColors.warning;
      case ContactPriority.far:
        return AppColors.errorColor;
    }
  }

  static List<DistanceResult> rank(List<CampusPerson> persons, LatLng target) {
    return persons.where((p) => p.displayLocation != null).map((p) {
      final gp = p.displayLocation!;
      final d = Geolocator.distanceBetween(
        target.latitude,
        target.longitude,
        gp.latitude,
        gp.longitude,
      );
      final prio = encode(d);
      return DistanceResult(
        person: p,
        distanceMeters: d,
        priority: prio,
        priorityLabel: priorityLabel(prio),
      );
    }).toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  }
}

// ─────────────────────────────────────────
//  AI DECISION ENGINE
//  FIX 1: Model identifier now comes from AnthropicConfig.model (.env)
// ─────────────────────────────────────────
class AiDecisionEngine {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  static Future<List<AiSuggestion>> getSuggestions(
    List<DistanceResult> ranked,
    CampusPerson targetPerson,
  ) async {
    if (ranked.isEmpty) return [];

    final ctx = ranked.take(5).map((r) {
      final avail = r.person.isOnline ? 'online' : 'offline';
      final ls = r.person.lastSeen != null
          ? '${DateTime.now().difference(r.person.lastSeen!).inMinutes} min ago'
          : 'unknown';
      return '- ${r.person.fullName} (${r.person.role}): '
          '${r.distanceText} away, priority=${r.priorityLabel}, '
          'status=$avail, last_seen=$ls';
    }).join('\n');

    final prompt = '''
You are an AI assistant for a university campus locator app.
The user needs to reach "${targetPerson.fullName}" (${targetPerson.role}).
People near the target ranked by proximity:
$ctx

For each person decide CALL or MESSAGE, give a one-sentence reason,
and a short ready-to-send message template.

Respond ONLY with valid JSON array — no markdown, no backticks:
[{"uid":"...","action":"call|message","reason":"...","messageTemplate":"..."}]
''';

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': AnthropicConfig.apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': AnthropicConfig.model, // FIX 1: from .env
          'max_tokens': 1000,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      if (response.statusCode != 200) return _fallback(ranked);

      final data = jsonDecode(response.body);
      final text = (data['content'] as List)
          .map((b) => b['type'] == 'text' ? b['text'] as String : '')
          .join('');
      final clean = text
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
      final List<dynamic> parsed = jsonDecode(clean);
      final suggestions = <AiSuggestion>[];
      for (final item in parsed) {
        final uid = item['uid'] as String?;
        final matched = ranked.firstWhere(
          (r) => r.person.uid == uid,
          orElse: () => ranked[suggestions.length % ranked.length],
        );
        suggestions.add(
          AiSuggestion(
            action: item['action'] ?? 'message',
            reason: item['reason'] ?? '',
            messageTemplate: item['messageTemplate'] ?? '',
            target: matched,
          ),
        );
      }
      return suggestions;
    } catch (_) {
      return _fallback(ranked);
    }
  }

  static List<AiSuggestion> _fallback(List<DistanceResult> ranked) {
    return ranked.take(3).map((r) {
      final online = r.person.isOnline;
      return AiSuggestion(
        action: online ? 'call' : 'message',
        reason: online
            ? '${r.person.firstName} is online and ${r.distanceText} away.'
            : '${r.person.firstName} is offline — '
                'last seen ${LastSeenHelper.format(r.person.lastSeen)}.',
        messageTemplate:
            'Hi ${r.person.firstName}, can you help me reach someone nearby?',
        target: r,
      );
    }).toList();
  }
}

// ─────────────────────────────────────────
//  PLACE NAME WIDGET
// ─────────────────────────────────────────
class _PlaceNameWidget extends StatefulWidget {
  final GeoPoint? geoPoint;
  final TextStyle? style;
  const _PlaceNameWidget({this.geoPoint, this.style});

  @override
  State<_PlaceNameWidget> createState() => _PlaceNameWidgetState();
}

class _PlaceNameWidgetState extends State<_PlaceNameWidget> {
  String _name = 'Loading...';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PlaceNameWidget old) {
    super.didUpdateWidget(old);
    if (old.geoPoint != widget.geoPoint) _load();
  }

  Future<void> _load() async {
    if (widget.geoPoint == null) {
      if (mounted) setState(() => _name = 'Unknown location');
      return;
    }
    final name = await GeocodingHelper.getPlaceName(
      widget.geoPoint!.latitude,
      widget.geoPoint!.longitude,
    );
    if (mounted) setState(() => _name = name);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _name,
      style:
          widget.style ?? const TextStyle(fontSize: 12, color: Colors.black54),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ─────────────────────────────────────────
//  OFFLINE STATUS BADGE
// ─────────────────────────────────────────
class _OfflineBadge extends StatelessWidget {
  final CampusPerson person;
  final bool compact;
  const _OfflineBadge({required this.person, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (person.isOnline) return const SizedBox.shrink();
    final ls = LastSeenHelper.format(person.lastSeen);
    final gp = person.lastLocation ?? person.location;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.access_time_rounded,
              size: 11,
              color: AppColors.offlineGrey,
            ),
            const SizedBox(width: 3),
            Text(
              ls,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.offlineGrey,
              ),
            ),
            if (gp != null) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.location_on_outlined,
                size: 11,
                color: AppColors.offlineGrey,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: _PlaceNameWidget(
                  geoPoint: gp,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.offlineGrey,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.offlineGrey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 13,
                color: AppColors.offlineGrey,
              ),
              const SizedBox(width: 5),
              Text(
                'Last seen: $ls',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.offlineGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (gp != null) ...[
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: AppColors.offlineGrey,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _PlaceNameWidget(
                    geoPoint: gp,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.offlineGrey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  INCOMING CALL LISTENER
//  FIX 3: Track active callDocId instead of boolean _dialogShown flag.
//         This prevents stale state when the Firestore stream reconnects
//         and correctly handles new calls after a previous one ends.
//  Also uses rootNavigator: true for dialog/navigation (original fix).
// ─────────────────────────────────────────
class IncomingCallListener extends StatefulWidget {
  final Widget child;
  const IncomingCallListener({super.key, required this.child});
  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  StreamSubscription? _sub;

  // FIX 3: Track by document ID, not a boolean
  String? _activeCallDocId;

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    _sub = FirebaseFirestore.instance
        .collection('calls')
        .where('calleeUid', isEqualTo: myUid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) {
      if (snap.docs.isEmpty) {
        // FIX 3: Reset when no ringing docs (call ended / declined)
        _activeCallDocId = null;
        return;
      }

      final doc = snap.docs.first;

      // FIX 3: Skip if we are already showing a dialog for this exact call
      if (_activeCallDocId == doc.id) return;

      _activeCallDocId = doc.id;
      final callerUid = doc['callerUid'] as String;
      _showIncomingDialog(callerUid, doc.id);
    });
  }

  void _showIncomingDialog(String callerUid, String callDocId) async {
    final callerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(callerUid)
        .get();
    if (!callerDoc.exists || !mounted) return;
    final caller = CampusPerson.fromFirestore(callerUid, callerDoc.data()!);

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.call_rounded, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Text(
              'Incoming Call',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Row(
          children: [
            CircleAvatar(
              backgroundColor: caller.roleColor.withOpacity(0.15),
              child: Text(
                caller.initials,
                style: TextStyle(
                  color: caller.roleColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caller.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    caller.role,
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.errorColor),
            icon: const Icon(Icons.call_end_rounded),
            label: const Text('Decline'),
            onPressed: () async {
              // FIX 3: Reset active call doc on decline
              _activeCallDocId = null;
              Navigator.of(ctx, rootNavigator: true).pop();
              await FirebaseFirestore.instance
                  .collection('calls')
                  .doc(callDocId)
                  .update({'status': 'ended'});
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.call_rounded, size: 16),
            label: const Text('Answer'),
            onPressed: () {
              // FIX 3: Reset active call doc on answer (screen takes over)
              _activeCallDocId = null;
              Navigator.of(ctx, rootNavigator: true).pop();
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) =>
                      InAppCallScreen(peer: caller, isOutgoing: false),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────
//  IN-APP CHAT SCREEN
// ─────────────────────────────────────────
class InAppChatScreen extends StatefulWidget {
  final CampusPerson peer;
  const InAppChatScreen({super.key, required this.peer});
  @override
  State<InAppChatScreen> createState() => _InAppChatScreenState();
}

class _InAppChatScreenState extends State<InAppChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late final String _myUid;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser!.uid;
    ChatService.markRead(_myUid, widget.peer.uid);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _ctrl.clear();
    await ChatService.sendMessage(
      myUid: _myUid,
      otherUid: widget.peer.uid,
      text: text,
    );
    if (mounted) setState(() => _sending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: const BackButton(color: AppColors.white),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: widget.peer.roleColor.withOpacity(0.3),
              child: Text(
                widget.peer.initials,
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peer.fullName,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.peer.isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: widget.peer.isOnline
                          ? AppColors.accent
                          : Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: AppColors.white),
            tooltip: 'In-app call',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    InAppCallScreen(peer: widget.peer, isOutgoing: true),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ChatService.messageStream(_myUid, widget.peer.uid),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 56,
                          color: Colors.black12,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.black38, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Say hi to ${widget.peer.firstName}!',
                          style: const TextStyle(
                            color: Colors.black26,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) {
                    _scroll.animateTo(
                      _scroll.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                });
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final isMe = d['from'] == _myUid;
                    final ts = d['ts'] != null
                        ? (d['ts'] as Timestamp).toDate()
                        : DateTime.now();
                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? AppColors.primary : AppColors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              d['text'] ?? '',
                              style: TextStyle(
                                color: isMe ? AppColors.white : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${ts.hour.toString().padLeft(2, '0')}:'
                              '${ts.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe ? Colors.white54 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: TextField(
                        controller: _ctrl,
                        maxLines: 4,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Type a message…',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: Colors.black38,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                color: AppColors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: AppColors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  IN-APP CALL SCREEN
//  FIX 5: Permission errors from _getLocalAudio are caught and shown
//  to the user with a snackbar before popping the screen.
// ─────────────────────────────────────────
class InAppCallScreen extends StatefulWidget {
  final CampusPerson peer;
  final bool isOutgoing;
  const InAppCallScreen({
    super.key,
    required this.peer,
    required this.isOutgoing,
  });
  @override
  State<InAppCallScreen> createState() => _InAppCallScreenState();
}

class _InAppCallScreenState extends State<InAppCallScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  bool _connected = false;
  bool _muted = false;
  int _seconds = 0;
  Timer? _timer;
  StreamSubscription? _callSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (widget.isOutgoing) {
        await CallService.startCall(_myUid, widget.peer.uid);
      } else {
        await CallService.answerCall(_myUid, widget.peer.uid);
        if (mounted) setState(() => _connected = true);
        _startTimer();
      }

      final ref = FirebaseFirestore.instance
          .collection('calls')
          .doc(ChatService.chatId(_myUid, widget.peer.uid));

      _callSub = ref.snapshots().listen((snap) {
        final status = snap.data()?['status'];
        if (status == 'active' && !_connected && mounted) {
          setState(() => _connected = true);
          _startTimer();
        }
        if (status == 'ended' && mounted) {
          _hangUp(remote: true);
        }
      });
    } catch (e) {
      if (mounted) {
        // FIX 5: Show permission error clearly before popping
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 5),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  String get _timeLabel {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _hangUp({bool remote = false}) async {
    _timer?.cancel();
    _callSub?.cancel();
    if (!remote) await CallService.hangUp(_myUid, widget.peer.uid);
    if (mounted) Navigator.pop(context);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    CallService.toggleMute(_muted);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 20),
            Column(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  child: Text(
                    widget.peer.initials,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  widget.peer.fullName,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _connected
                      ? _timeLabel
                      : widget.isOutgoing
                          ? 'Calling…'
                          : 'Connecting…',
                  style: const TextStyle(color: Colors.white60, fontSize: 16),
                ),
                if (_connected) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.accent.withOpacity(0.4),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          color: AppColors.accent,
                          size: 13,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'In-app call · end-to-end',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _callBtn(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _muted ? 'Unmute' : 'Mute',
                    color: Colors.white.withOpacity(0.15),
                    iconColor: AppColors.white,
                    onTap: _toggleMute,
                  ),
                  _callBtn(
                    icon: Icons.call_end_rounded,
                    label: 'End Call',
                    color: AppColors.errorColor,
                    iconColor: AppColors.white,
                    size: 72,
                    onTap: _hangUp,
                  ),
                  _callBtn(
                    icon: Icons.volume_up_rounded,
                    label: 'Speaker',
                    color: Colors.white.withOpacity(0.15),
                    iconColor: AppColors.white,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _callBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    double size = 60,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: size * 0.42),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  PROFILE EDIT SCREEN
// ─────────────────────────────────────────
class ProfileEditScreen extends StatefulWidget {
  final Map<String, dynamic> currentData;
  const ProfileEditScreen({super.key, required this.currentData});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _rollCtrl;
  late final TextEditingController _parentCtrl;
  late final TextEditingController _empCtrl;
  late String _role;

  @override
  void initState() {
    super.initState();
    final d = widget.currentData;
    _role = d['role'] ?? 'Student';
    _firstCtrl = TextEditingController(text: d['firstName'] ?? '');
    _lastCtrl = TextEditingController(text: d['lastName'] ?? '');
    _phoneCtrl = TextEditingController(text: d['phone'] ?? '');
    _rollCtrl = TextEditingController(text: d['rollNumber'] ?? '');
    _parentCtrl = TextEditingController(text: d['parentEmail'] ?? '');
    _empCtrl = TextEditingController(text: d['employeeId'] ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _firstCtrl,
      _lastCtrl,
      _phoneCtrl,
      _rollCtrl,
      _parentCtrl,
      _empCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Color get _accent {
    switch (_role) {
      case 'Faculty':
        return AppColors.facultyAccent;
      case 'Others':
        return AppColors.othersAccent;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final updates = <String, dynamic>{
      'firstName': _firstCtrl.text.trim(),
      'lastName': _lastCtrl.text.trim(),
      'phone':
          _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
    };
    if (_role == 'Student') {
      updates['rollNumber'] = _rollCtrl.text.trim();
      updates['parentEmail'] = _parentCtrl.text.trim();
    } else if (_role == 'Faculty') {
      updates['employeeId'] = _empCtrl.text.trim();
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.white,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text('Profile updated!'),
              ],
            ),
            backgroundColor: AppColors.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: _accent,
        elevation: 0,
        leading: const BackButton(color: AppColors.white),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 46,
                  backgroundColor: _accent.withOpacity(0.15),
                  child: Text(
                    '${_firstCtrl.text.isNotEmpty ? _firstCtrl.text[0].toUpperCase() : '?'}'
                    '${_lastCtrl.text.isNotEmpty ? _lastCtrl.text[0].toUpperCase() : ''}',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _role,
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _sectionHeader('Personal Info'),
              const SizedBox(height: 14),
              Card(
                elevation: 2,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _editField(
                        ctrl: _firstCtrl,
                        label: 'First Name',
                        icon: Icons.person_outline,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const Divider(height: 20),
                      _editField(
                        ctrl: _lastCtrl,
                        label: 'Last Name',
                        icon: Icons.person_outline,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const Divider(height: 20),
                      _editField(
                        ctrl: _phoneCtrl,
                        label: 'Phone Number (optional)',
                        icon: Icons.phone_outlined,
                        type: TextInputType.phone,
                      ),
                    ],
                  ),
                ),
              ),
              if (_role == 'Student') ...[
                const SizedBox(height: 20),
                _sectionHeader('Student Info'),
                const SizedBox(height: 14),
                Card(
                  elevation: 2,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _editField(
                          ctrl: _rollCtrl,
                          label: 'Roll Number',
                          icon: Icons.badge_outlined,
                        ),
                        const Divider(height: 20),
                        _editField(
                          ctrl: _parentCtrl,
                          label: 'Parent Email',
                          icon: Icons.family_restroom_outlined,
                          type: TextInputType.emailAddress,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_role == 'Faculty') ...[
                const SizedBox(height: 20),
                _sectionHeader('Faculty Info'),
                const SizedBox(height: 14),
                Card(
                  elevation: 2,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _editField(
                      ctrl: _empCtrl,
                      label: 'Employee ID',
                      icon: Icons.work_outline,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.amber,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Email and role cannot be changed. '
                        'Contact admin if needed.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      );

  Widget _editField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType? type,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _accent.withOpacity(0.8), fontSize: 14),
        prefixIcon: Icon(icon, color: _accent, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  APP
// ─────────────────────────────────────────
class CampusLocatorApp extends StatefulWidget {
  const CampusLocatorApp({super.key});
  @override
  State<CampusLocatorApp> createState() => _CampusLocatorAppState();
}

class _CampusLocatorAppState extends State<CampusLocatorApp> {
  AppLifecycleObserver? _observer;

  @override
  void dispose() {
    if (_observer != null) WidgetsBinding.instance.removeObserver(_observer!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Locator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: AppColors.primary),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }
          if (snapshot.hasData) {
            final uid = snapshot.data!.uid;
            if (_observer == null || _observer!.uid != uid) {
              if (_observer != null) {
                WidgetsBinding.instance.removeObserver(_observer!);
              }
              _observer = AppLifecycleObserver(uid);
              WidgetsBinding.instance.addObserver(_observer!);
            }
            LocationService.startTracking(uid);
            return const HomeScreen();
          }
          if (_observer != null) {
            WidgetsBinding.instance.removeObserver(_observer!);
            _observer = null;
          }
          LocationService.stopTracking();
          return const AuthScreen();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────
//  SPLASH
// ─────────────────────────────────────────
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_rounded, size: 90, color: AppColors.white),
            SizedBox(height: 20),
            Text(
              'Campus Locator',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'University Portal',
              style: TextStyle(color: Colors.white60, fontSize: 15),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(color: AppColors.white, strokeWidth: 2.5),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  HOME SCREEN
//  IncomingCallListener wraps the entire Scaffold (original fix).
// ─────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<Map<String, dynamic>?> _getUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return IncomingCallListener(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
          title: const Row(
            children: [
              Icon(Icons.school_rounded, color: AppColors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'Campus Locator',
                style: TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: AppColors.white),
              tooltip: 'Edit Profile',
              onPressed: () async {
                final data = await _getUserData();
                if (data == null || !mounted) return;
                final refreshed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileEditScreen(currentData: data),
                  ),
                );
                if (refreshed == true && mounted) setState(() {});
              },
            ),
            IconButton(
              icon: const Icon(Icons.people_rounded, color: AppColors.white),
              tooltip: 'People',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PeopleScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: AppColors.white),
              tooltip: 'Logout',
              onPressed: () async {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) await LocationService.goOffline(uid);
                LocationService.stopTracking();
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: _getUserData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            final data = snapshot.data;
            final role = data?['role'] ?? 'User';
            final firstName = data?['firstName'] ?? '';
            final lastName = data?['lastName'] ?? '';
            final fullName = '$firstName $lastName'.trim();
            final displayName =
                fullName.isNotEmpty ? fullName : user?.email ?? 'User';

            Color roleColor = AppColors.primary;
            IconData roleIcon = Icons.school_rounded;
            if (role == 'Faculty') {
              roleColor = AppColors.facultyAccent;
              roleIcon = Icons.menu_book_rounded;
            } else if (role == 'Others') {
              roleColor = AppColors.othersAccent;
              roleIcon = Icons.people_rounded;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [roleColor, roleColor.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: roleColor.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            roleIcon,
                            size: 36,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            role,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _LiveLocationCard(),
                  const SizedBox(height: 24),
                  if (data != null) ...[
                    _sectionHeader('Profile Details', roleColor),
                    const SizedBox(height: 14),
                    Card(
                      elevation: 3,
                      shadowColor: Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _profileTile(
                              Icons.person_rounded,
                              'Full Name',
                              displayName,
                              roleColor,
                            ),
                            _divider(),
                            _profileTile(
                              Icons.email_rounded,
                              'Email',
                              user?.email ?? '-',
                              roleColor,
                            ),
                            if (data['phone'] != null) ...[
                              _divider(),
                              _profileTile(
                                Icons.phone_rounded,
                                'Phone',
                                data['phone'],
                                roleColor,
                              ),
                            ],
                            if (role == 'Student') ...[
                              _divider(),
                              _profileTile(
                                Icons.badge_rounded,
                                'Roll Number',
                                data['rollNumber'] ?? '-',
                                roleColor,
                              ),
                              _divider(),
                              _profileTile(
                                Icons.family_restroom_rounded,
                                'Parent Email',
                                data['parentEmail'] ?? '-',
                                roleColor,
                              ),
                            ],
                            if (role == 'Faculty') ...[
                              _divider(),
                              _profileTile(
                                Icons.work_rounded,
                                'Employee ID',
                                data['employeeId'] ?? '-',
                                roleColor,
                              ),
                            ],
                            _divider(),
                            _profileTile(
                              Icons.verified_user_rounded,
                              'Role',
                              role,
                              roleColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _sectionHeader('Quick Actions', roleColor),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _actionCard(
                          Icons.map_rounded,
                          'Campus Map',
                          'Find locations',
                          roleColor,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PeopleScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionCard(
                          Icons.schedule_rounded,
                          'Schedule',
                          'View timetable',
                          roleColor,
                          null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _actionCard(
                          Icons.notifications_rounded,
                          'Notices',
                          'Announcements',
                          roleColor,
                          null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionCard(
                          Icons.contact_support_rounded,
                          'Support',
                          'Get help',
                          roleColor,
                          null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) => Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      );

  Widget _divider() => const Divider(height: 1, color: Color(0xFFEEEEEE));

  Widget _profileTile(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  LIVE LOCATION CARD
// ─────────────────────────────────────────
class _LiveLocationCard extends StatefulWidget {
  const _LiveLocationCard();
  @override
  State<_LiveLocationCard> createState() => _LiveLocationCardState();
}

class _LiveLocationCardState extends State<_LiveLocationCard> {
  Position? _pos;
  String _placeName = 'Getting location name...';
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen((p) async {
      if (!mounted) return;
      setState(() => _pos = p);
      final name = await GeocodingHelper.getPlaceName(
        p.latitude,
        p.longitude,
      );
      if (mounted) setState(() => _placeName = name);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.my_location_rounded,
              color: AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live Location Active',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _pos != null ? _placeName : 'Waiting for GPS signal...',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_pos != null)
                  Text(
                    '${_pos!.latitude.toStringAsFixed(5)}, '
                    '${_pos!.longitude.toStringAsFixed(5)}  '
                    '±${_pos!.accuracy.toStringAsFixed(0)}m',
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _pos != null ? AppColors.accent : Colors.orange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_pos != null ? AppColors.accent : Colors.orange)
                      .withOpacity(0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  AUTH SCREEN
//  forgotPassword context captured before async gap (original fix).
// ─────────────────────────────────────────
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _loading = false;
  String _role = 'Student';
  final List<String> _roles = ['Student', 'Faculty', 'Others'];

  final _loginKey = GlobalKey<FormState>();
  final _registerKey = GlobalKey<FormState>();

  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _parentCtrl = TextEditingController();
  final _empCtrl = TextEditingController();

  String _generatedOtp = '';
  bool _otpSent = false;
  bool _otpSending = false;
  bool _otpVerified = false;
  int _countdown = 0;

  bool _loginPassVis = false;
  bool _regPassVis = false;
  bool _confirmVis = false;

  @override
  void dispose() {
    for (final c in [
      _loginEmailCtrl,
      _loginPassCtrl,
      _regEmailCtrl,
      _passCtrl,
      _confirmCtrl,
      _otpCtrl,
      _firstCtrl,
      _lastCtrl,
      _phoneCtrl,
      _rollCtrl,
      _parentCtrl,
      _empCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Color get _accent {
    switch (_role) {
      case 'Faculty':
        return AppColors.facultyAccent;
      case 'Others':
        return AppColors.othersAccent;
      default:
        return AppColors.primary;
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_rounded : Icons.check_circle_rounded,
              color: AppColors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: error ? AppColors.errorColor : AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _generateOtp() => (100000 + Random().nextInt(900000)).toString();

  Future<void> _sendOtp() async {
    final email = _regEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Enter a valid email first', error: true);
      return;
    }
    setState(() => _otpSending = true);
    final otp = _generateOtp();
    try {
      await FirebaseFirestore.instance.collection('email_otps').doc(email).set({
        'otp': otp,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      final response = await http
          .post(
            Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
            headers: {
              'Content-Type': 'application/json',
              'origin': 'http://localhost',
            },
            body: jsonEncode({
              'service_id': EmailJSConfig.serviceId, // FIX 2: from .env
              'template_id': EmailJSConfig.templateId, // FIX 2: from .env
              'user_id': EmailJSConfig.publicKey, // FIX 2: from .env
              'template_params': {
                'to_email': email,
                'otp_code': otp,
                'app_name': 'Campus Locator',
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      setState(() {
        _generatedOtp = otp;
        _otpSent = true;
        _countdown = 30;
      });
      _startCountdown();

      if (response.statusCode == 200) {
        _snack('OTP sent to $email ✓ Check inbox');
      } else {
        _snack('EmailJS error. Test OTP: $otp', error: true);
      }
    } catch (_) {
      setState(() {
        _generatedOtp = otp;
        _otpSent = true;
        _countdown = 30;
      });
      _startCountdown();
      _snack('Network error. Test OTP: $otp', error: true);
    } finally {
      if (mounted) setState(() => _otpSending = false);
    }
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      return _countdown > 0;
    });
  }

  Future<void> _verifyOtp() async {
    final email = _regEmailCtrl.text.trim();
    final entered = _otpCtrl.text.trim();
    if (entered.isEmpty) {
      _snack('Enter the OTP', error: true);
      return;
    }
    if (entered == _generatedOtp) {
      setState(() => _otpVerified = true);
      _snack('OTP verified ✓');
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('email_otps')
          .doc(email)
          .get();
      if (!doc.exists) {
        _snack('OTP expired. Request a new one.', error: true);
        return;
      }
      final data = doc.data()!;
      final storedOtp = data['otp'] as String?;
      final expiresAt = data['expiresAt'] as int?;
      if (expiresAt != null &&
          DateTime.now().millisecondsSinceEpoch > expiresAt) {
        _snack('OTP expired. Request a new one.', error: true);
        await FirebaseFirestore.instance
            .collection('email_otps')
            .doc(email)
            .delete();
        return;
      }
      if (entered == storedOtp) {
        setState(() => _otpVerified = true);
        _snack('OTP verified ✓');
      } else {
        _snack('Invalid OTP.', error: true);
      }
    } catch (_) {
      _snack('Verification failed.', error: true);
    }
  }

  Future<void> _login() async {
    if (!_loginKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _loginEmailCtrl.text.trim(),
        password: _loginPassCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      _snack(_errMsg(e.code), error: true);
    } catch (_) {
      _snack('Something went wrong.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (!_registerKey.currentState!.validate()) return;
    if (!_otpVerified) {
      _snack('Verify OTP first', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _regEmailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      final Map<String, dynamic> profile = {
        'role': _role,
        'email': _regEmailCtrl.text.trim(),
        'firstName': _firstCtrl.text.trim(),
        'lastName': _lastCtrl.text.trim(),
        'phone':
            _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        'createdAt': FieldValue.serverTimestamp(),
        'isOnline': false,
        'lastLocation': null,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      if (_role == 'Student') {
        profile['rollNumber'] = _rollCtrl.text.trim();
        profile['parentEmail'] = _parentCtrl.text.trim();
      } else if (_role == 'Faculty') {
        profile['employeeId'] = _empCtrl.text.trim();
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set(profile);
      await FirebaseFirestore.instance
          .collection('email_otps')
          .doc(_regEmailCtrl.text.trim())
          .delete();
      _snack('Account created successfully!');
    } on FirebaseAuthException catch (e) {
      _snack(_errMsg(e.code), error: true);
    } catch (_) {
      _snack('Something went wrong.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final scaffoldCtx = context; // capture before async gap
    final emailCtrl = TextEditingController(text: _loginEmailCtrl.text.trim());
    bool sending = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: _accent, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Reset Password',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your registered email. We\'ll send a reset link.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: TextStyle(
                    color: _accent.withOpacity(0.8),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: _accent,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _accent, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.black45),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onPressed: sending
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                          SnackBar(
                            content: const Text('Enter a valid email'),
                            backgroundColor: AppColors.errorColor,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => sending = true);
                      try {
                        await FirebaseAuth.instance.sendPasswordResetEmail(
                          email: email,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                          SnackBar(
                            content: Text('Reset email sent to $email ✓'),
                            backgroundColor: AppColors.accent,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() => sending = false);
                        ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                          SnackBar(
                            content: Text(_errMsg(e.code)),
                            backgroundColor: AppColors.errorColor,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                      } catch (_) {
                        setDialogState(() => sending = false);
                      }
                    },
              icon: sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(sending ? 'Sending…' : 'Send Reset Link'),
            ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }

  String _errMsg(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account for this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'Email already registered.';
      case 'weak-password':
        return 'Password too weak (min 6 chars).';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Try later.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return 'Something went wrong.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildRoleSelector(),
            const SizedBox(height: 20),
            _buildCard(),
            _buildFooter(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      height: 240,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accent, _accent.withOpacity(0.65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(50),
          bottomRight: Radius.circular(50),
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  size: 36,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isLogin ? 'Welcome Back!' : 'Create Account',
                  key: ValueKey(_isLogin),
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isLogin ? 'Sign in as $_role' : 'Register as $_role',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SegmentedButton<String>(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: _accent,
          selectedForegroundColor: AppColors.white,
          side: BorderSide(color: _accent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        segments: _roles
            .map(
              (r) => ButtonSegment(
                value: r,
                label: Text(
                  r,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            )
            .toList(),
        selected: {_role},
        onSelectionChanged: (s) => setState(() => _role = s.first),
      ),
    );
  }

  Widget _buildCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                child: child,
              ),
            ),
            child: _isLogin ? _loginForm() : _registerForm(),
          ),
        ),
      ),
    );
  }

  Widget _loginForm() {
    return Form(
      key: _loginKey,
      child: Column(
        key: const ValueKey('login'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionBar('Sign In'),
          const SizedBox(height: 20),
          _field(
            _loginEmailCtrl,
            'Email Address',
            Icons.email_outlined,
            type: TextInputType.emailAddress,
            validator: (v) => (v == null || v.isEmpty)
                ? 'Email required'
                : !v.contains('@')
                    ? 'Enter valid email'
                    : null,
          ),
          const SizedBox(height: 14),
          _passField(
            _loginPassCtrl,
            'Password',
            Icons.lock_outline,
            visible: _loginPassVis,
            onToggle: () => setState(() => _loginPassVis = !_loginPassVis),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Password required' : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _forgotPassword,
              child: Text(
                'Forgot password?',
                style: TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _btn('LOGIN', _login),
        ],
      ),
    );
  }

  Widget _registerForm() {
    return Form(
      key: _registerKey,
      child: Column(
        key: const ValueKey('register'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionBar('Personal Info'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _field(
                  _firstCtrl,
                  'First Name',
                  Icons.person_outline,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  _lastCtrl,
                  'Last Name',
                  Icons.person_outline,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _field(
            _phoneCtrl,
            'Phone Number (optional)',
            Icons.phone_outlined,
            type: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          if (_role == 'Student') ...[
            _field(
              _rollCtrl,
              'Roll Number',
              Icons.badge_outlined,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            _field(
              _parentCtrl,
              'Parent Email',
              Icons.family_restroom_outlined,
              type: TextInputType.emailAddress,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
          ],
          if (_role == 'Faculty') ...[
            _field(
              _empCtrl,
              'Employee ID',
              Icons.work_outline,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
          ],
          _sectionBar('Account Info'),
          const SizedBox(height: 16),
          _field(
            _regEmailCtrl,
            'Email Address',
            Icons.email_outlined,
            type: TextInputType.emailAddress,
            suffix: _otpSending
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _countdown > 0 ? null : _sendOtp,
                    child: Text(
                      _countdown > 0 ? '${_countdown}s' : 'Get OTP',
                      style: TextStyle(
                        color: _countdown > 0 ? Colors.black38 : _accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
            validator: (v) => (v == null || v.isEmpty)
                ? 'Email required'
                : !v.contains('@')
                    ? 'Enter valid email'
                    : null,
          ),
          if (_otpSent) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    decoration: _dec(
                      'Enter OTP',
                      Icons.vpn_key_outlined,
                      suffix: _otpVerified
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.accent,
                              size: 20,
                            )
                          : null,
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter OTP' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _otpVerified ? AppColors.accent : _accent,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _otpVerified ? null : _verifyOtp,
                    child: Text(
                      _otpVerified ? '✓' : 'Verify',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            if (_otpVerified)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Row(
                  children: const [
                    Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.accent,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Email verified successfully',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          _passField(
            _passCtrl,
            'Password',
            Icons.lock_outline,
            visible: _regPassVis,
            onToggle: () => setState(() => _regPassVis = !_regPassVis),
            validator: (v) =>
                (v == null || v.length < 6) ? 'Min 6 characters' : null,
          ),
          const SizedBox(height: 14),
          _passField(
            _confirmCtrl,
            'Confirm Password',
            Icons.lock_clock_outlined,
            visible: _confirmVis,
            onToggle: () => setState(() => _confirmVis = !_confirmVis),
            validator: (v) =>
                v != _passCtrl.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 28),
          _btn('CREATE ACCOUNT', _register),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: TextButton(
        onPressed: () => setState(() {
          _isLogin = !_isLogin;
          _otpSent = false;
          _otpVerified = false;
          _countdown = 0;
          _generatedOtp = '';
          _loginKey.currentState?.reset();
          _registerKey.currentState?.reset();
        }),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Colors.black54),
            children: [
              TextSpan(
                text: _isLogin
                    ? "Don't have an account? "
                    : "Already have an account? ",
              ),
              TextSpan(
                text: _isLogin ? 'Register Now' : 'Login',
                style: TextStyle(color: _accent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionBar(String title) => Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      );

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _accent.withOpacity(0.8), fontSize: 14),
      prefixIcon: Icon(icon, color: _accent, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.errorColor, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.errorColor, width: 2),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? type,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      inputFormatters: formatters,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: _dec(label, icon, suffix: suffix),
    );
  }

  Widget _passField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    required bool visible,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: !visible,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: _dec(
        label,
        icon,
        suffix: IconButton(
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: _accent,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  Widget _btn(String label, Future<void> Function() action) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: AppColors.white,
          elevation: 4,
          shadowColor: _accent.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _loading ? null : action,
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  PEOPLE SCREEN
// ─────────────────────────────────────────
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  Position? _myPosition;
  CampusPerson? _myProfile;
  bool _locationLoading = true;
  StreamSubscription<Position>? _locationSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _init();
  }

  Future<void> _init() async {
    await _loadMyProfile();
    await _setupLocation();
  }

  Future<void> _loadMyProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && mounted) {
      setState(() => _myProfile = CampusPerson.fromFirestore(uid, doc.data()!));
    }
  }

  Future<void> _setupLocation() async {
    final pos = await LocationService.getPermissionAndPosition();
    if (pos != null && mounted) {
      setState(() {
        _myPosition = pos;
        _locationLoading = false;
      });
    } else {
      if (mounted) setState(() => _locationLoading = false);
    }
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (mounted) setState(() => _myPosition = pos);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _locationSub?.cancel();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.errorColor : AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tab,
        children: [
          _NearbyTab(myPosition: _myPosition, myProfile: _myProfile),
          _ConnectionsTab(myProfile: _myProfile, onSnack: _snack),
          _FindPeopleTab(
            myProfile: _myProfile,
            myPosition: _myPosition,
            onSnack: _snack,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      leading: const BackButton(color: AppColors.white),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              _myProfile?.initials ?? '?',
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _myProfile?.fullName ?? 'Loading...',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _myPosition != null
                      ? '${_myPosition!.latitude.toStringAsFixed(4)}, '
                          '${_myPosition!.longitude.toStringAsFixed(4)}'
                      : _locationLoading
                          ? 'Getting GPS...'
                          : 'Location unavailable',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _myPosition != null ? AppColors.accent : Colors.orange,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        (_myPosition != null ? AppColors.accent : Colors.orange)
                            .withOpacity(0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_rounded,
                color: AppColors.white,
              ),
              onPressed: () => _showNotifications(context),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('connection_requests')
                    .where(
                      'toUid',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                    )
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.errorColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: TabBar(
        controller: _tab,
        indicatorColor: AppColors.accent,
        indicatorWeight: 3,
        labelColor: AppColors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(icon: Icon(Icons.map_rounded, size: 18), text: 'Nearby'),
          Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'Connections'),
          Tab(icon: Icon(Icons.search_rounded, size: 18), text: 'Find People'),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) =>
          _NotificationsPanel(currentUid: uid, parentContext: context),
    );
  }
}

// ─────────────────────────────────────────
//  NOTIFICATIONS PANEL
// ─────────────────────────────────────────
class _NotificationsPanel extends StatelessWidget {
  final String currentUid;
  final BuildContext parentContext;
  const _NotificationsPanel({
    required this.currentUid,
    required this.parentContext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notifications',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('connection_requests')
                  .where('toUid', isEqualTo: currentUid)
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No new notifications',
                      style: TextStyle(color: Colors.black45),
                    ),
                  );
                }
                final docs = snap.data!.docs;
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        child: Text(
                          (d['fromName'] ?? '?')[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        d['fromName'] ?? 'Someone',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text('Wants to connect with you'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _reqBtn(
                            context,
                            docs[i].id,
                            d,
                            'accepted',
                            AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          _reqBtn(
                            context,
                            docs[i].id,
                            d,
                            'rejected',
                            AppColors.errorColor,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _reqBtn(
    BuildContext ctx,
    String docId,
    Map<String, dynamic> data,
    String status,
    Color color,
  ) {
    return GestureDetector(
      onTap: () async {
        await FirebaseFirestore.instance
            .collection('connection_requests')
            .doc(docId)
            .update({'status': status});

        if (status == 'accepted') {
          final fromUid = data['fromUid'] as String;
          final toUid = data['toUid'] as String;
          await FirebaseFirestore.instance
              .collection('connections')
              .doc('${fromUid}_$toUid')
              .set({
            'users': [fromUid, toUid],
            'createdAt': FieldValue.serverTimestamp(),
          });
          if (ctx.mounted) Navigator.pop(ctx);
          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: Text(
                'Connected with ${data['fromName']}! '
                'You can now see each other\'s location.',
              ),
              backgroundColor: AppColors.accent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        } else {
          if (ctx.mounted) Navigator.pop(ctx);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          status == 'accepted' ? 'Accept' : 'Decline',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  TAB 1 – NEARBY
// ─────────────────────────────────────────
class _NearbyTab extends StatefulWidget {
  final Position? myPosition;
  final CampusPerson? myProfile;
  const _NearbyTab({this.myPosition, this.myProfile});
  @override
  State<_NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<_NearbyTab> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(_NearbyTab old) {
    super.didUpdateWidget(old);
    if (widget.myPosition != null && widget.myPosition != old.myPosition) {
      _mapController.move(
        LatLng(widget.myPosition!.latitude, widget.myPosition!.longitude),
        17.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.myPosition == null) return _locationError();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search nearby places or people…',
                hintStyle: const TextStyle(fontSize: 14, color: Colors.black38),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
                suffixIcon: widget.myPosition != null
                    ? const Icon(
                        Icons.my_location_rounded,
                        color: AppColors.accent,
                        size: 22,
                      )
                    : const Icon(
                        Icons.location_off_rounded,
                        color: Colors.black38,
                        size: 22,
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
        Expanded(flex: 3, child: _mapLayer()),
        Expanded(flex: 2, child: _nearbyList()),
      ],
    );
  }

  Widget _mapLayer() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snap) {
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final markers = <Marker>[];

        if (widget.myPosition != null) {
          markers.add(
            Marker(
              point: LatLng(
                widget.myPosition!.latitude,
                widget.myPosition!.longitude,
              ),
              width: 44,
              height: 44,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          );
        }

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            if (doc.id == myUid) continue;
            final p = CampusPerson.fromFirestore(
              doc.id,
              doc.data() as Map<String, dynamic>,
            );
            final gp = p.displayLocation;
            if (gp == null) continue;

            final dotColor = p.isOnline
                ? (p.role == 'Faculty'
                    ? AppColors.purple
                    : p.role == 'Others'
                        ? AppColors.warning
                        : AppColors.primary)
                : AppColors.offlineGrey;

            markers.add(
              Marker(
                point: LatLng(gp.latitude, gp.longitude),
                width: 44,
                height: 44,
                child: GestureDetector(
                  onTap: () => _showPersonDialog(context, p),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: dotColor.withOpacity(0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        p.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }

        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(
              widget.myPosition!.latitude,
              widget.myPosition!.longitude,
            ),
            initialZoom: 17.0,
            maxZoom: 19.0,
            minZoom: 3.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.campus_locator',
              maxZoom: 19,
            ),
            MarkerLayer(markers: markers),
          ],
        );
      },
    );
  }

  void _showPersonDialog(BuildContext context, CampusPerson p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(p.fullName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.role),
            const SizedBox(height: 4),
            Text(
              p.isOnline ? '🟢 Online' : '⚫ Offline',
              style: TextStyle(
                color: p.isOnline ? AppColors.accent : AppColors.offlineGrey,
              ),
            ),
            if (!p.isOnline) ...[
              const SizedBox(height: 6),
              Text(
                'Last seen: ${LastSeenHelper.format(p.lastSeen)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.offlineGrey,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Location:',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            _PlaceNameWidget(geoPoint: p.displayLocation),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _nearbyList() {
    if (widget.myPosition == null) {
      return const Center(
        child: Text(
          'Enable location to see nearby people',
          style: TextStyle(color: Colors.black45),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final myLatLng = LatLng(
          widget.myPosition!.latitude,
          widget.myPosition!.longitude,
        );
        final people = snap.data!.docs
            .where((d) => d.id != myUid)
            .map(
              (d) => CampusPerson.fromFirestore(
                d.id,
                d.data() as Map<String, dynamic>,
              ),
            )
            .where((p) => p.location != null)
            .toList();
        final ranked = VerilogDistanceRanker.rank(
          people,
          myLatLng,
        ).where((r) => r.distanceMeters <= 2000).toList();
        if (ranked.isEmpty) {
          return const Center(
            child: Text(
              'No one nearby right now',
              style: TextStyle(color: Colors.black45),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '${ranked.length} people nearby',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: ranked.length,
                itemBuilder: (_, i) => _NearbyTile(result: ranked[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _locationError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_rounded,
                size: 60, color: Colors.black26),
            const SizedBox(height: 12),
            const Text(
              'Location permission required',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enable location to see nearby people',
              style: TextStyle(color: Colors.black45, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async => await Geolocator.openLocationSettings(),
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      );
}

class _NearbyTile extends StatelessWidget {
  final DistanceResult result;
  const _NearbyTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final p = result.person;
    final c = VerilogDistanceRanker.priorityColor(result.priority);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      shadowColor: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: p.roleColor.withOpacity(0.15),
                  child: Text(
                    p.initials,
                    style: TextStyle(
                      color: p.roleColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color:
                          p.isOnline ? AppColors.accent : AppColors.offlineGrey,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    p.role,
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                  _OfflineBadge(person: p, compact: true),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.withOpacity(0.3)),
                  ),
                  child: Text(
                    result.distanceText,
                    style: TextStyle(
                      color: c,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  result.priorityLabel,
                  style: TextStyle(color: c, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  TAB 2 – CONNECTIONS
// ─────────────────────────────────────────
class _ConnectionsTab extends StatelessWidget {
  final CampusPerson? myProfile;
  final void Function(String, {bool error}) onSnack;
  const _ConnectionsTab({this.myProfile, required this.onSnack});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('connections')
          .where('users', arrayContains: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return _empty();

        final otherUids = docs
            .map((d) {
              final users = List<String>.from(d['users']);
              return users.firstWhere((u) => u != uid, orElse: () => '');
            })
            .where((u) => u.isNotEmpty)
            .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Connections (${docs.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<CampusPerson>>(
                future: _fetch(otherUids),
                builder: (context, pSnap) {
                  if (!pSnap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: pSnap.data!.length,
                    itemBuilder: (_, i) => _ConnTile(person: pSnap.data![i]),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<CampusPerson>> _fetch(List<String> uids) async {
    final results = await Future.wait(
      uids.map(
        (uid) => FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .then(
              (d) =>
                  d.exists ? CampusPerson.fromFirestore(uid, d.data()!) : null,
            ),
      ),
    );
    return results.whereType<CampusPerson>().toList();
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.group_add_rounded, size: 64, color: Colors.black26),
            SizedBox(height: 12),
            Text(
              'No connections yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 6),
            Text(
              'Find and add people from the Find tab',
              style: TextStyle(color: Colors.black45, fontSize: 13),
            ),
          ],
        ),
      );
}

class _ConnTile extends StatelessWidget {
  final CampusPerson person;
  const _ConnTile({required this.person});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      shadowColor: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: person.roleColor.withOpacity(0.15),
                  child: Text(
                    person.initials,
                    style: TextStyle(
                      color: person.roleColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: person.isOnline
                          ? AppColors.accent
                          : AppColors.offlineGrey,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${person.role} · '
                    '${person.isOnline ? "Online" : "Offline"}',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  if (person.displayLocation != null)
                    _PlaceNameWidget(
                      geoPoint: person.displayLocation,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                      ),
                    ),
                  _OfflineBadge(person: person, compact: true),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ib(Icons.location_on_rounded, AppColors.accent, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _PersonLocationScreen(person: person),
                    ),
                  );
                }),
                const SizedBox(width: 6),
                _ib(Icons.call_rounded, AppColors.primary, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          InAppCallScreen(peer: person, isOutgoing: true),
                    ),
                  );
                }),
                const SizedBox(width: 6),
                _ib(Icons.message_rounded, AppColors.purple, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InAppChatScreen(peer: person),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ib(IconData icon, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      );
}

// ─────────────────────────────────────────
//  PERSON LOCATION SCREEN
// ─────────────────────────────────────────
class _PersonLocationScreen extends StatefulWidget {
  final CampusPerson person;
  const _PersonLocationScreen({required this.person});
  @override
  State<_PersonLocationScreen> createState() => _PersonLocationScreenState();
}

class _PersonLocationScreenState extends State<_PersonLocationScreen> {
  List<DistanceResult> _ranked = [];
  List<AiSuggestion> _aiSuggestions = [];
  bool _loading = true;
  bool _aiLoading = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final connected = await ConnectionService.areMutuallyConnected(
      myUid,
      widget.person.uid,
    );

    if (!connected) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _loading = false;
        });
      }
      return;
    }
    setState(() => _isConnected = true);

    final gp = widget.person.displayLocation;
    if (gp == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final target = LatLng(gp.latitude, gp.longitude);
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final connectedUids = await ConnectionService.getConnectedUids(myUid);
    final others = snap.docs
        .where(
          (d) =>
              d.id != myUid &&
              d.id != widget.person.uid &&
              connectedUids.contains(d.id),
        )
        .map((d) => CampusPerson.fromFirestore(d.id, d.data()))
        .toList();

    final ranked = VerilogDistanceRanker.rank(others, target);
    if (mounted) {
      setState(() {
        _ranked = ranked;
        _loading = false;
      });
    }
    _fetchAI(ranked);
  }

  Future<void> _fetchAI(List<DistanceResult> ranked) async {
    if (ranked.isEmpty) return;
    setState(() => _aiLoading = true);
    final sug = await AiDecisionEngine.getSuggestions(ranked, widget.person);
    if (mounted) {
      setState(() {
        _aiSuggestions = sug;
        _aiLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          widget.person.fullName,
          style: const TextStyle(color: AppColors.white),
        ),
        leading: const BackButton(color: AppColors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: AppColors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    InAppCallScreen(peer: widget.person, isOutgoing: true),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.message_rounded, color: AppColors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InAppChatScreen(peer: widget.person),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : !_isConnected
              ? _accessDenied()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _targetCard(),
                      const SizedBox(height: 20),
                      _secTitle(
                        'People near ${widget.person.firstName}',
                        '${_ranked.length} found',
                        Icons.group_rounded,
                      ),
                      const SizedBox(height: 12),
                      ..._ranked.take(10).map(
                            (r) =>
                                _RankedCard(result: r, target: widget.person),
                          ),
                      const SizedBox(height: 20),
                      _secTitle(
                        'AI Decision Suggestions',
                        'Powered by Claude',
                        Icons.auto_awesome_rounded,
                        color: AppColors.purple,
                      ),
                      const SizedBox(height: 12),
                      if (_aiLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                              color: AppColors.purple,
                            ),
                          ),
                        )
                      else if (_aiSuggestions.isEmpty)
                        const Text(
                          'No AI suggestions available.',
                          style: TextStyle(color: Colors.black45),
                        )
                      else
                        ..._aiSuggestions.map((s) => _AiCard(suggestion: s)),
                    ],
                  ),
                ),
    );
  }

  Widget _accessDenied() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.errorColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 56,
                  color: AppColors.errorColor,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Location Access Restricted',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You need to be connected with '
                '${widget.person.firstName} to view their location.',
                style: const TextStyle(color: Colors.black54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );

  Widget _targetCard() {
    final p = widget.person;
    final gp = p.displayLocation;
    final c = p.isOnline ? p.roleColor : AppColors.offlineGrey;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c, c.withOpacity(0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.25),
            child: Text(
              p.initials,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fullName,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  p.role,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    p.isOnline ? '🟢 Online' : '⚫ Offline',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (gp != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _PlaceNameWidget(
                          geoPoint: gp,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!p.isOnline)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Last seen: ${LastSeenHelper.format(p.lastSeen)}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secTitle(
    String title,
    String sub,
    IconData icon, {
    Color color = AppColors.primary,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              sub,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ],
    );
  }
}

class _RankedCard extends StatelessWidget {
  final DistanceResult result;
  final CampusPerson target;
  const _RankedCard({required this.result, required this.target});

  @override
  Widget build(BuildContext context) {
    final p = result.person;
    final c = VerilogDistanceRanker.priorityColor(result.priority);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.withOpacity(0.3)),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _rank(result.priority).toString(),
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 20,
              backgroundColor: p.roleColor.withOpacity(0.15),
              child: Text(
                p.initials,
                style: TextStyle(
                  color: p.roleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    p.role,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  _PlaceNameWidget(
                    geoPoint: p.displayLocation,
                    style: const TextStyle(fontSize: 10, color: Colors.black38),
                  ),
                  _OfflineBadge(person: p, compact: true),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  result.distanceText,
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.priorityLabel,
                    style: TextStyle(
                      color: c,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          InAppCallScreen(peer: p, isOutgoing: true),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: (p.isOnline
                              ? AppColors.primary
                              : AppColors.offlineGrey)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.call_rounded,
                      color: p.isOnline
                          ? AppColors.primary
                          : AppColors.offlineGrey,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => InAppChatScreen(peer: p)),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.message_rounded,
                      color: AppColors.purple,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _rank(ContactPriority p) {
    switch (p) {
      case ContactPriority.nearest:
        return 1;
      case ContactPriority.close:
        return 2;
      case ContactPriority.moderate:
        return 3;
      case ContactPriority.far:
        return 4;
    }
  }
}

class _AiCard extends StatelessWidget {
  final AiSuggestion suggestion;
  const _AiCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final isCall = suggestion.action == 'call';
    final isOnline = suggestion.target.person.isOnline;
    final canCall = isCall && isOnline;
    final color = canCall ? AppColors.primary : AppColors.purple;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  canCall ? Icons.call_rounded : Icons.message_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      canCall
                          ? 'Recommended: In-app Call'
                          : 'Recommended: Message',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      suggestion.target.person.fullName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    _PlaceNameWidget(
                      geoPoint: suggestion.target.person.displayLocation,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: VerilogDistanceRanker.priorityColor(
                    suggestion.target.priority,
                  ).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  suggestion.target.distanceText,
                  style: TextStyle(
                    color: VerilogDistanceRanker.priorityColor(
                      suggestion.target.priority,
                    ),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              suggestion.reason,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.format_quote_rounded,
                  size: 14,
                  color: Colors.black38,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    suggestion.messageTemplate,
                    style: const TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOnline ? color : AppColors.offlineGrey,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: Icon(
                canCall ? Icons.call_rounded : Icons.send_rounded,
                size: 16,
              ),
              label: Text(
                canCall
                    ? 'Call Now (In-app)'
                    : !isOnline
                        ? 'Offline — Send Message'
                        : 'Send Message',
              ),
              onPressed: isOnline
                  ? canCall
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InAppCallScreen(
                                peer: suggestion.target.person,
                                isOutgoing: true,
                              ),
                            ),
                          )
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InAppChatScreen(
                                peer: suggestion.target.person,
                              ),
                            ),
                          )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  TAB 3 – FIND PEOPLE
// ─────────────────────────────────────────
class _FindPeopleTab extends StatefulWidget {
  final CampusPerson? myProfile;
  final Position? myPosition;
  final void Function(String, {bool error}) onSnack;
  const _FindPeopleTab({
    this.myProfile,
    this.myPosition,
    required this.onSnack,
  });
  @override
  State<_FindPeopleTab> createState() => _FindPeopleTabState();
}

class _FindPeopleTabState extends State<_FindPeopleTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Map<String, bool> _connCache = {};
  final Map<String, bool> _reqCache = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<bool> _isConnected(String uid) async {
    if (_connCache.containsKey(uid)) return _connCache[uid]!;
    final my = FirebaseAuth.instance.currentUser?.uid ?? '';
    final result = await ConnectionService.areMutuallyConnected(my, uid);
    return _connCache[uid] = result;
  }

  Future<bool> _reqSent(String uid) async {
    if (_reqCache.containsKey(uid)) return _reqCache[uid]!;
    final my = FirebaseAuth.instance.currentUser?.uid ?? '';
    final q = await FirebaseFirestore.instance
        .collection('connection_requests')
        .where('fromUid', isEqualTo: my)
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .get();
    return _reqCache[uid] = q.docs.isNotEmpty;
  }

  Future<void> _sendReq(CampusPerson target) async {
    final my = FirebaseAuth.instance.currentUser?.uid ?? '';
    final name = widget.myProfile?.fullName ?? 'Someone';
    await FirebaseFirestore.instance.collection('connection_requests').add({
      'fromUid': my,
      'fromName': name,
      'toUid': target.uid,
      'toName': target.fullName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() => _reqCache[target.uid] = true);
    widget.onSnack(
      'Request sent! Location visible after '
      '${target.firstName} accepts.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search by name, role or roll number…',
                hintStyle: TextStyle(fontSize: 13, color: Colors.black38),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              final docs = snap.data!.docs
                  .where((d) => d.id != myUid)
                  .map(
                    (d) => CampusPerson.fromFirestore(
                      d.id,
                      d.data() as Map<String, dynamic>,
                    ),
                  )
                  .where((p) {
                if (_query.isEmpty) return true;
                return p.fullName.toLowerCase().contains(_query) ||
                    p.role.toLowerCase().contains(_query) ||
                    (p.rollNumber?.toLowerCase().contains(_query) ?? false) ||
                    p.email.toLowerCase().contains(_query);
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.search_off_rounded,
                        size: 60,
                        color: Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _query.isEmpty
                            ? 'No users found'
                            : 'No results for "$_query"',
                        style: const TextStyle(color: Colors.black45),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: docs.length,
                itemBuilder: (_, i) => _FindTile(
                  person: docs[i],
                  myPosition: widget.myPosition,
                  isConnected: _isConnected,
                  requestSent: _reqSent,
                  onSendRequest: _sendReq,
                  onSnack: widget.onSnack,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FindTile extends StatefulWidget {
  final CampusPerson person;
  final Position? myPosition;
  final Future<bool> Function(String) isConnected;
  final Future<bool> Function(String) requestSent;
  final Future<void> Function(CampusPerson) onSendRequest;
  final void Function(String, {bool error}) onSnack;
  const _FindTile({
    required this.person,
    this.myPosition,
    required this.isConnected,
    required this.requestSent,
    required this.onSendRequest,
    required this.onSnack,
  });
  @override
  State<_FindTile> createState() => _FindTileState();
}

class _FindTileState extends State<_FindTile> {
  bool? _connected, _sent;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final c = await widget.isConnected(widget.person.uid);
    final s = await widget.requestSent(widget.person.uid);
    if (mounted) {
      setState(() {
        _connected = c;
        _sent = s;
      });
    }
  }

  String? get _distText {
    if (_connected != true) return null;
    if (widget.myPosition == null || widget.person.location == null) {
      return null;
    }
    final d = Geolocator.distanceBetween(
      widget.myPosition!.latitude,
      widget.myPosition!.longitude,
      widget.person.location!.latitude,
      widget.person.location!.longitude,
    );
    return d < 1000
        ? '${d.toStringAsFixed(0)} m'
        : '${(d / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final isConn = _connected == true;
    final sent = _sent == true;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      shadowColor: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: p.roleColor.withOpacity(0.15),
                  child: Text(
                    p.initials,
                    style: TextStyle(
                      color: p.roleColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color:
                          p.isOnline ? AppColors.accent : AppColors.offlineGrey,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    [
                      p.role,
                      if (p.rollNumber != null) p.rollNumber!,
                      if (_distText != null) _distText!,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  _OfflineBadge(person: p, compact: true),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _connected == null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : isConn
                    ? _btn(
                        Icons.location_on_rounded,
                        'Location',
                        AppColors.accent,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _PersonLocationScreen(person: p),
                            ),
                          );
                        },
                      )
                    : sent
                        ? _chip('Requested', Colors.orange)
                        : _btn(
                            Icons.person_add_rounded,
                            'Connect',
                            AppColors.primary,
                            _working
                                ? null
                                : () async {
                                    setState(() => _working = true);
                                    await widget.onSendRequest(p);
                                    setState(() {
                                      _working = false;
                                      _sent = true;
                                    });
                                  },
                          ),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
}
