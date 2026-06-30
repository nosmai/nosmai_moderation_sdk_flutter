import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nosmai_moderation_sdk_flutter/nosmai_moderation_sdk_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'live_screen.dart';

void main() => runApp(const NosmaiExampleApp());

const _bg = Color(0xFF0B0B0C);
const _card = Color(0xFF161618);
const _cardHi = Color(0xFF242427);
const _border = Color(0xFF2C2C30);
const _muted = Color(0xFF9A9AA0);

class NosmaiExampleApp extends StatelessWidget {
  const NosmaiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nosmai Moderation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        fontFamily: '.SF Pro Text',
        colorScheme: const ColorScheme.dark(
          surface: _card,
          primary: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();

  String _engine = 'Starting…';
  bool _ready = false;
  bool _busy = false;
  bool _picking = false;
  File? _media;
  bool _isVideo = false;
  _Verdict? _verdict;

  // Text moderation (separate engine — loads after the visual engine).
  final TextEditingController _textCtrl = TextEditingController();
  bool _textReady = false;
  bool _textBusy = false;
  NosmaiTextResult? _textResult;

  @override
  void initState() {
    super.initState();
    _initSdk();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSdk() async {
    // Replace with a real, backend-registered license key.
    var init = await NosmaiModeration.initialize(
      Platform.isIOS
          ? 'NOSMAI-XXXX' // your iOS license key (for this app's bundle id)
          : 'NOSMAI-XXXX', // your Android license key (for this app's package id)
      // Load object detection + NSFW; the text model loads separately via
      // initializeText() below.
      models: const [NosmaiModel.objectDetection, NosmaiModel.nsfw],
    );
    if (!mounted) return;
    setState(() {
      _ready = init.success == true;
      _engine = _ready
          ? 'Engine ready'
          : 'Engine: ${init.error ?? 'not ready'}';
    });
    // The text model (~26 MB) is heavy; load it after the visual engine is up.
    if (_ready) _initText();
  }

  Future<void> _initText() async {
    final ok = await NosmaiModeration.initializeText();
    if (!mounted) return;
    setState(() => _textReady = ok);
  }

  Future<void> _checkText() async {
    final msg = _textCtrl.text.trim();
    if (msg.isEmpty || _textBusy || !_textReady) return;
    FocusScope.of(context).unfocus();
    setState(() => _textBusy = true);
    final r = await NosmaiModeration.moderateText(msg);
    if (!mounted) return;
    setState(() {
      _textBusy = false;
      _textResult = r;
    });
  }

  // ---- Pick / capture ----

  Future<bool> _ensure(Permission p) async {
    var status = await p.status;
    if (status.isGranted || status.isLimited) return true;
    status = await p.request();
    if (status.isGranted || status.isLimited) return true;
    if (status.isPermanentlyDenied) {
      _snack('Permission denied. Enable it in Settings.');
      await openAppSettings();
    }
    return false;
  }

  Future<void> _pickImage(ImageSource source) async {
    // image_picker allows only one active request; a second tap before the first
    // returns throws "Cancelled by a second request". Guard re-entry.
    if (_busy || _picking) return;
    setState(() => _picking = true);
    try {
      if (source == ImageSource.camera && !await _ensure(Permission.camera)) {
        return _snack('Camera permission denied');
      }
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );
      if (file == null) return;
      setState(() {
        _media = File(file.path);
        _isVideo = false;
        _verdict = null;
      });
      await _runImage(file.path);
    } on PlatformException catch (e) {
      _snack('Picker error: ${e.code}');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_busy || _picking) return;
    setState(() => _picking = true);
    try {
      if (source == ImageSource.camera && !await _ensure(Permission.camera)) {
        return _snack('Camera permission denied');
      }
      final XFile? file = await _picker.pickVideo(source: source);
      if (file == null) return;
      setState(() {
        _media = File(file.path);
        _isVideo = true;
        _verdict = null;
      });
      await _runVideo(file.path);
    } on PlatformException catch (e) {
      _snack('Picker error: ${e.code}');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  // ---- Moderate ----

  Future<void> _runImage(String path) async {
    setState(() => _busy = true);
    final r = await NosmaiModeration.analyzeImage(path);
    if (!mounted) return;
    setState(() {
      _verdict = _Verdict.fromImage(r);
      _busy = false;
    });
  }

  Future<void> _runVideo(String path) async {
    setState(() => _busy = true);
    final r = await NosmaiModeration.analyzeVideo(path);
    if (!mounted) return;
    setState(() {
      _verdict = _Verdict.fromVideo(r);
      _busy = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _cardHi));
  }

  Widget _textCard() {
    final canCheck = _textReady && !_textBusy;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.chat_bubble_outline,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Text moderation',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _textReady ? 'ready' : 'loading…',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textCtrl,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _checkText(),
            decoration: InputDecoration(
              hintText: 'Type a message to check…',
              hintStyle: const TextStyle(color: _muted),
              filled: true,
              fillColor: _cardHi,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: canCheck ? _checkText : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: canCheck ? Colors.white : _cardHi,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _textBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      'Check text',
                      style: TextStyle(
                        color: canCheck ? Colors.black : _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          if (_textResult != null) ...[
            const SizedBox(height: 12),
            _textResultRow(_textResult!),
          ],
        ],
      ),
    );
  }

  Widget _textResultRow(NosmaiTextResult r) {
    final blocked = r.blocked == true;
    final parts = <String>[];
    if (blocked) {
      if (r.category != null && r.category != NosmaiTextCategory.safe) {
        parts.add(r.category!.name);
      }
      if (r.layer != null && r.layer != NosmaiTextLayer.none) {
        parts.add(r.layer!.name);
      }
      if ((r.matchedWord ?? '').isNotEmpty) parts.add('"${r.matchedWord}"');
      if ((r.score ?? 0) > 0) parts.add('${((r.score ?? 0) * 100).round()}%');
    }
    final label = blocked ? 'BLOCKED' : 'CLEAN';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: blocked ? Colors.white : _cardHi,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            blocked ? Icons.block : Icons.check_circle_outline,
            color: blocked ? Colors.black : Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.isEmpty ? label : '$label · ${parts.join(' · ')}',
              style: TextStyle(
                color: blocked ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _preview(),
                    const SizedBox(height: 20),
                    if (_busy)
                      _analyzing()
                    else if (_verdict != null)
                      _verdictCard(_verdict!),
                    const SizedBox(height: 20),
                    _textCard(),
                  ],
                ),
              ),
            ),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nosmai',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'On-device moderation',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
          const Spacer(),
          _liveButton(),
          const SizedBox(width: 10),
          _statusPill(),
        ],
      ),
    );
  }

  Widget _liveButton() {
    return GestureDetector(
      onTap: _ready
          ? () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const LiveScreen()))
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _ready ? Colors.white : _cardHi,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 16,
              color: _ready ? Colors.black : _muted,
            ),
            const SizedBox(width: 6),
            Text(
              'Live',
              style: TextStyle(
                color: _ready ? Colors.black : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _ready ? Colors.white : _muted,
            ),
          ),
          const SizedBox(width: 8),
          Text(_engine, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _preview() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _media == null
            ? _emptyPreview()
            : _isVideo
            ? _videoPreview()
            : Image.file(_media!, fit: BoxFit.cover),
      ),
    );
  }

  Widget _emptyPreview() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: _muted, size: 48),
          SizedBox(height: 12),
          Text(
            'Pick or capture media to check',
            style: TextStyle(color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _videoPreview() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.movie_outlined, color: Colors.white, size: 48),
          const SizedBox(height: 10),
          Text(
            _media!.path.split('/').last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _analyzing() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 14),
          Text('Analyzing…', style: TextStyle(color: _muted)),
        ],
      ),
    );
  }

  Widget _verdictCard(_Verdict v) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: v.background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: v.background == Colors.white ? Colors.white : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(v.icon, color: v.foreground, size: 30),
              const SizedBox(width: 12),
              Text(
                v.label,
                style: TextStyle(
                  color: v.foreground,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          if (v.details.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: v.details.map((d) => _chip(d, v.foreground)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color fg) {
    final onWhite = fg == Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: onWhite
            ? Colors.black.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _actions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          _actionButton(
            Icons.photo_library_outlined,
            'Image',
            () => _pickImage(ImageSource.gallery),
          ),
          const SizedBox(width: 10),
          _actionButton(
            Icons.video_library_outlined,
            'Video',
            () => _pickVideo(ImageSource.gallery),
          ),
          const SizedBox(width: 10),
          _actionButton(
            Icons.photo_camera_outlined,
            'Camera',
            () => _pickImage(ImageSource.camera),
            primary: true,
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool primary = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: (_busy || _picking) ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: primary ? Colors.white : _cardHi,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primary ? Colors.white : _border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: primary ? Colors.black : Colors.white,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: primary ? Colors.black : Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Display model: maps a moderation result to a monochrome verdict (severity is
/// shown by shade — SAFE outlined, SUGGESTIVE mid-grey, UNSAFE inverted white).
class _Verdict {
  _Verdict(
    this.label,
    this.details,
    this.icon,
    this.background,
    this.foreground,
  );

  final String label;
  final List<String> details;
  final IconData icon;
  final Color background;
  final Color foreground;

  static _Verdict _build(
    bool unsafe,
    NosmaiNsfwVerdict? nsfw,
    List<String> details,
  ) {
    if (unsafe) {
      return _Verdict(
        'UNSAFE',
        details,
        Icons.block,
        Colors.white,
        Colors.black,
      );
    }
    if (nsfw == NosmaiNsfwVerdict.warn) {
      return _Verdict(
        'SUGGESTIVE',
        details,
        Icons.visibility_outlined,
        _cardHi,
        Colors.white,
      );
    }
    return _Verdict(
      'SAFE',
      details,
      Icons.verified_outlined,
      _card,
      Colors.white,
    );
  }

  factory _Verdict.fromImage(NosmaiResult r) {
    final details = <String>[];
    // Type the fallback list so `d` keeps its enum type — `EnumName.name` is an
    // extension getter and won't resolve on a `dynamic` receiver.
    for (final d in r.detections ?? const <NosmaiObjectDetection?>[]) {
      if (d == null) continue;
      final cat = d.category?.name ?? 'object';
      details.add('$cat ${((d.confidence ?? 0) * 100).round()}%');
    }
    if (r.nsfw == NosmaiNsfwVerdict.block) {
      details.add('NSFW explicit ${((r.nsfwExplicit ?? 0) * 100).round()}%');
    } else if (r.nsfw == NosmaiNsfwVerdict.warn) {
      details.add('NSFW suggestive ${((r.nsfwSexy ?? 0) * 100).round()}%');
    }
    if (details.isEmpty) details.add('Nothing detected');
    return _build(r.isUnsafe == true, r.nsfw, details);
  }

  factory _Verdict.fromVideo(NosmaiVideoResult r) {
    final details = <String>[];
    for (final c in r.categories ?? const <NosmaiCategory?>[]) {
      if (c != null) details.add(c.name);
    }
    if (r.nsfw == NosmaiNsfwVerdict.block) {
      details.add('NSFW explicit');
    } else if (r.nsfw == NosmaiNsfwVerdict.warn) {
      details.add('NSFW suggestive');
    }
    details.add('${r.framesAnalyzed ?? 0} frames');
    return _build(r.isUnsafe == true, r.nsfw, details);
  }
}
