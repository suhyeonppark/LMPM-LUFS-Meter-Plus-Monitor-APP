import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// 한 번 수신한 LUFS 측정값 묶음. 값은 `-inf` → `null` 직렬화 규칙 때문에
/// 비어 있을 수 있으므로 nullable 로 둔다.
class LufsReading {
  const LufsReading({
    this.momentary,
    this.shortTerm,
    this.integrated,
    required this.receivedAt,
    required this.fromAddress,
  });

  final double? momentary;
  final double? shortTerm;
  final double? integrated;

  /// 패킷을 받은 로컬 시각. 송신측 `ts` 와는 별개로, "신호 끊김" 판정에 쓴다.
  final DateTime receivedAt;
  final String fromAddress;
}

/// 플러그인이 보내는 UDP 브로드캐스트(`{"type":"lufs",...}`)를 49152 포트에서 수신한다.
///
/// 외부 패키지 없이 dart:io 만 사용한다. 안드로이드 일부 기기는 절전을 위해
/// 브로드캐스트 패킷을 필터링하므로, 가능하면 네이티브 MulticastLock 을
/// 잡는다(없어도 동작은 함 — README 참고).
class LufsListener {
  LufsListener({this.port = 49152, this.controlPort = 49153});

  final int port;

  /// 플러그인이 리셋 같은 제어 명령을 수신하는 포트.
  final int controlPort;

  static const _multicastLockChannel = MethodChannel('lufs/multicast');

  RawDatagramSocket? _socket;
  final _controller = StreamController<LufsReading>.broadcast();

  /// 새 측정값이 들어올 때마다 방출된다.
  Stream<LufsReading> get readings => _controller.stream;

  bool get isBound => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;

    // anyIPv4 + 해당 포트에 bind 하면 브로드캐스트(255.255.255.255)로 오는
    // 패킷도 그대로 받는다. reuseAddress 로 재실행 시 bind 충돌을 피한다.
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    _socket = socket;

    await _acquireMulticastLock();

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      _handleDatagram(datagram);
    });
  }

  void _handleDatagram(Datagram datagram) {
    String text;
    try {
      text = utf8.decode(datagram.data);
    } catch (_) {
      return; // UTF-8 이 아니면 우리 패킷이 아님
    }

    Map<String, dynamic> map;
    try {
      final decoded = json.decode(text);
      if (decoded is! Map<String, dynamic>) return;
      map = decoded;
    } catch (_) {
      return; // JSON 이 아니면 무시
    }

    if (map['type'] != 'lufs') return; // 다른 메시지 타입과 구분

    _controller.add(
      LufsReading(
        momentary: _toDouble(map['momentary']),
        shortTerm: _toDouble(map['shortTerm']),
        integrated: _toDouble(map['integrated']),
        receivedAt: DateTime.now(),
        fromAddress: datagram.address.address,
      ),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null; // null / "null" / 결측은 모두 측정 안 됨으로 처리
  }

  Future<void> _acquireMulticastLock() async {
    try {
      await _multicastLockChannel.invokeMethod('acquire');
    } on MissingPluginException {
      // 네이티브 코드를 추가하지 않은 경우. 대부분 기기는 락 없이도 수신됨.
    } catch (_) {
      // 잡지 못해도 치명적이지 않으므로 조용히 무시.
    }
  }

  /// 플러그인에 측정 리셋 명령을 보낸다. 최근 패킷을 받은 주소가 있으면 그쪽으로
  /// 유니캐스트하고, 아직 없으면 브로드캐스트로 흩뿌린다. 수신용 소켓을 그대로
  /// 재사용하므로 별도 bind 가 필요 없다.
  void sendReset([String? toAddress]) {
    final socket = _socket;
    if (socket == null) return;

    final data = utf8.encode('{"type":"reset"}');
    final target = (toAddress != null && toAddress.isNotEmpty)
        ? InternetAddress(toAddress)
        : InternetAddress('255.255.255.255');
    try {
      socket.send(data, target, controlPort);
    } catch (_) {
      // 전송 실패는 치명적이지 않으므로 조용히 무시.
    }
  }

  Future<void> dispose() async {
    _socket?.close();
    _socket = null;
    try {
      await _multicastLockChannel.invokeMethod('release');
    } catch (_) {}
    await _controller.close();
  }
}
