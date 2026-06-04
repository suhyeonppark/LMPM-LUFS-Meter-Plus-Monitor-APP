import 'dart:async';

import 'package:flutter/material.dart';

import 'lufs_listener.dart';
import 'pip.dart';

void main() => runApp(const LufsMonitorApp());

class LufsMonitorApp extends StatelessWidget {
  const LufsMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LMPM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111316),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4FA3FF),
          surface: Color(0xFF1A1D21),
        ),
        useMaterial3: true,
      ),
      home: const MonitorPage(),
    );
  }
}

/// 연결 상태 4단계.
enum LinkStatus {
  starting, // 소켓 bind 시도 중
  listening, // bind 됨, 아직 패킷 없음
  receiving, // 최근에 패킷 수신 중
  idle, // 받다가 끊김(플러그인 idle / 오디오 정지)
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final _listener = LufsListener();
  final _pip = PipController();

  // 플러그인은 1초 간격으로 보낸다. 2.5초 안 오면 끊긴 것으로 본다.
  static const _staleAfter = Duration(milliseconds: 2500);

  StreamSubscription<LufsReading>? _sub;
  StreamSubscription<bool>? _pipSub;
  Timer? _ticker;

  LufsReading? _last;
  Object? _error;
  bool _inPip = false;
  bool _pipSupported = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}), // 경과시간/상태 갱신용
    );
    _startListening();
    _setupPip();
  }

  Future<void> _setupPip() async {
    _pipSub = _pip.pipModeChanges.listen(
      (inPip) => setState(() => _inPip = inPip),
    );
    final supported = await _pip.isSupported();
    if (mounted) setState(() => _pipSupported = supported);
  }

  Future<void> _startListening() async {
    try {
      await _listener.start();
      _sub = _listener.readings.listen((reading) {
        _pip.updateReading(
          momentary: reading.momentary,
          shortTerm: reading.shortTerm,
          integrated: reading.integrated,
        );
        setState(() {
          _last = reading;
          _error = null;
        });
      });
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e);
    }
  }

  LinkStatus get _status {
    if (_error != null || !_listener.isBound) return LinkStatus.starting;
    final last = _last;
    if (last == null) return LinkStatus.listening;
    final age = DateTime.now().difference(last.receivedAt);
    return age <= _staleAfter ? LinkStatus.receiving : LinkStatus.idle;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    _pipSub?.cancel();
    _pip.dispose();
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final last = _last;

    // 떠 있는 작은 창에서는 INTEGRATED 값만 크게 보여준다.
    if (_inPip) {
      return _PipReadout(status: status, reading: last);
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                status: status,
                reading: last,
                onEnterPip: _pipSupported ? _pip.enter : null,
                onReset: () {
                  _listener.sendReset(last?.fromAddress);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('측정 리셋 신호를 보냈습니다'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: _PrimaryReadout(
                    label: 'INTEGRATED',
                    value: last?.integrated,
                    dimmed: status == LinkStatus.idle ||
                        status == LinkStatus.listening,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _SecondaryReadout(
                      label: 'MOMENTARY',
                      value: last?.momentary,
                      dimmed: status != LinkStatus.receiving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SecondaryReadout(
                      label: 'SHORT-TERM',
                      value: last?.shortTerm,
                      dimmed: status != LinkStatus.receiving,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Footer(reading: last, error: _error),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.status,
    required this.reading,
    this.onEnterPip,
    this.onReset,
  });

  final LinkStatus status;
  final LufsReading? reading;

  /// PiP 지원 기기에서만 채워진다. null 이면 버튼을 숨긴다.
  final Future<void> Function()? onEnterPip;

  /// 플러그인에 측정 리셋 신호를 보낸다. null 이면 버튼을 숨긴다.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (status) {
      LinkStatus.starting => (Colors.grey, '시작 중…'),
      LinkStatus.listening => (const Color(0xFF8A93A0), '대기 중 (신호 없음)'),
      LinkStatus.receiving => (const Color(0xFF35D07F), '수신 중'),
      LinkStatus.idle => (const Color(0xFF8A93A0), '신호 끊김'),
    };

    return Row(
      children: [
        const Text(
          'LMPM',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        if (onReset != null) ...[
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.refresh),
            iconSize: 22,
            color: const Color(0xFF8A93A0),
            tooltip: '측정 리셋',
            visualDensity: VisualDensity.compact,
          ),
        ],
        if (onEnterPip != null) ...[
          IconButton(
            onPressed: () => onEnterPip!(),
            icon: const Icon(Icons.picture_in_picture_alt),
            iconSize: 22,
            color: const Color(0xFF8A93A0),
            tooltip: '작은 창으로 보기',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrimaryReadout extends StatelessWidget {
  const _PrimaryReadout({
    required this.label,
    required this.value,
    required this.dimmed,
  });

  final String label;
  final double? value;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? const Color(0xFF4A5159) : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8A93A0),
            fontSize: 16,
            letterSpacing: 4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              formatLufs(value),
              style: TextStyle(
                color: color,
                fontSize: 88,
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.0,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'LUFS',
                style: TextStyle(
                  color: color.withValues(alpha: 0.6),
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SecondaryReadout extends StatelessWidget {
  const _SecondaryReadout({
    required this.label,
    required this.value,
    required this.dimmed,
  });

  final String label;
  final double? value;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? const Color(0xFF4A5159) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D21),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8A93A0),
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatLufs(value),
                style: TextStyle(
                  color: color,
                  fontSize: 34,
                  fontWeight: FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'LUFS',
                style: TextStyle(
                  color: color.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.reading, required this.error});

  final LufsReading? reading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    String text;
    if (error != null) {
      text = '포트 49152 열기 실패: $error';
    } else if (reading == null) {
      text = 'UDP :49152 수신 대기 — PC와 같은 WiFi 인지 확인하세요';
    } else {
      final age = DateTime.now().difference(reading!.receivedAt);
      final ago = age.inMilliseconds < 1500
          ? '방금'
          : '${age.inSeconds}초 전';
      text = '${reading!.fromAddress} · UDP :49152 · 마지막 수신 $ago';
    }

    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: error != null ? const Color(0xFFE05A5A) : const Color(0xFF6A727C),
        fontSize: 12,
      ),
    );
  }
}

/// 떠 있는 작은 창(PiP) 전용 화면 — INTEGRATED 를 크게, MOMENTARY/SHORT-TERM 을
/// 그 아래 작게 함께 보여준다. 창 크기가 매우 작을 수 있으므로 FittedBox 로 자동 축소한다.
class _PipReadout extends StatelessWidget {
  const _PipReadout({required this.status, required this.reading});

  final LinkStatus status;
  final LufsReading? reading;

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (status) {
      LinkStatus.receiving => const Color(0xFF35D07F),
      _ => const Color(0xFF8A93A0), // 끊김/대기/시작 모두 회색(꺼진 느낌)
    };
    final dimmed = status != LinkStatus.receiving;
    final textColor = dimmed ? const Color(0xFF6A727C) : Colors.white;
    final subColor = dimmed ? const Color(0xFF4A5159) : const Color(0xFFB6BDC6);

    return Scaffold(
      backgroundColor: const Color(0xFF111316),
      body: Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // INTEGRATED — 가장 크게.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          formatLufs(reading?.integrated),
                          style: TextStyle(
                            color: textColor,
                            fontSize: 72,
                            fontWeight: FontWeight.w300,
                            height: 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'LUFS',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.6),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // MOMENTARY / SHORT-TERM — 한 줄에 작게.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _pipMini('M', reading?.momentary, subColor),
                        const SizedBox(width: 18),
                        _pipMini('S', reading?.shortTerm, subColor),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pipMini(String label, double? value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          formatLufs(value),
          style: TextStyle(
            color: color,
            fontSize: 26,
            fontWeight: FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// `-23.41` → `-23.4`, null(측정 안 됨) → `—`.
String formatLufs(double? value) {
  if (value == null || !value.isFinite) return '—';
  return value.toStringAsFixed(1);
}
