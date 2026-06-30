import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nosmai_moderation_sdk_flutter/nosmai_moderation_sdk_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

const _bg = Color(0xFF0B0B0C);
const _card = Color(0xFF161618);
const _cardHi = Color(0xFF242427);
const _border = Color(0xFF2C2C30);
const _muted = Color(0xFF9A9AA0);

/// Live camera moderation. The preview + detection run natively; this screen just
/// shows the native preview on top and the latest per-frame result below.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  StreamSubscription<NosmaiResult>? _sub;
  NosmaiResult? _result;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    _sub = NosmaiLive.results().listen((r) {
      if (mounted) setState(() => _result = r);
    });
    await NosmaiLive.start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    NosmaiLive.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _bar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _denied
                      ? _deniedView()
                      : const NosmaiCameraPreview(),
                ),
              ),
            ),
            _resultPanel(),
          ],
        ),
      ),
    );
  }

  Widget _bar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Text(
            'Live moderation',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deniedView() {
    return Container(
      color: _card,
      alignment: Alignment.center,
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Camera permission denied.\nEnable it in Settings to use live moderation.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
      ),
    );
  }

  Widget _resultPanel() {
    final unsafe = _result?.isUnsafe == true;
    final nsfw = _result?.nsfw;
    final label = unsafe
        ? 'UNSAFE'
        : (nsfw == NosmaiNsfwVerdict.warn ? 'SUGGESTIVE' : 'SAFE');
    final onWhite = unsafe;

    final chips = <String>[];
    for (final d in _result?.detections ?? const <NosmaiObjectDetection?>[]) {
      if (d == null) continue;
      final cat = d.category?.name ?? 'object';
      chips.add('$cat ${((d.confidence ?? 0) * 100).round()}%');
    }
    if (nsfw == NosmaiNsfwVerdict.block) {
      chips.add('NSFW explicit ${((_result?.nsfwExplicit ?? 0) * 100).round()}%');
    } else if (nsfw == NosmaiNsfwVerdict.warn) {
      chips.add('NSFW suggestive ${((_result?.nsfwSexy ?? 0) * 100).round()}%');
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: unsafe ? Colors.white : _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: unsafe ? Colors.white : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unsafe
                    ? Icons.block
                    : (nsfw == NosmaiNsfwVerdict.warn
                          ? Icons.visibility_outlined
                          : Icons.verified_outlined),
                color: onWhite ? Colors.black : Colors.white,
                size: 26,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: onWhite ? Colors.black : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                'live',
                style: TextStyle(
                  color: onWhite ? Colors.black54 : _muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips
                  .map(
                    (c) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: onWhite
                            ? Colors.black.withValues(alpha: 0.06)
                            : _cardHi,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                          color: onWhite ? Colors.black : Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
