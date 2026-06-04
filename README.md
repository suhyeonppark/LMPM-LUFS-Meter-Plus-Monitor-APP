# LUFS Monitor (스마트폰 앱)

LUFS Meter Plus 플러그인이 **UDP 브로드캐스트**로 1초마다 뿌리는 라우드니스
값을 받아, 폰 화면에 크게 표시하는 Flutter 앱입니다.

```
┌──────────────────────────────┐
│ LUFS Monitor          ● 수신 중 │
│                              │
│           INTEGRATED         │
│         -14.2  LUFS          │
│                              │
│ ┌ MOMENTARY ─┐ ┌ SHORT-TERM ┐ │
│ │ -13.8 LUFS │ │ -14.5 LUFS │ │
│ └────────────┘ └────────────┘ │
│ 192.168.0.12 · :49152 · 방금  │
└──────────────────────────────┘
```

- **Integrated** 를 가장 크게, **Momentary / Short-term** 을 아래에 작게 표시
- 상단에 **연결 상태** 표시: `대기 중` → `수신 중`(초록) → `신호 끊김`(주황)
- 측정이 아직 안 된 값(`null`)은 `—` 로 표시

전제: **폰과 PC(플러그인 실행 머신)가 같은 WiFi/LAN(같은 서브넷)** 에 있어야
합니다. 브로드캐스트는 라우터(L3)를 넘지 못합니다.

---

## 프로토콜 (플러그인 → 앱)

| 항목 | 값 |
| --- | --- |
| 전송 | UDP 브로드캐스트 `255.255.255.255` |
| 포트 | `49152` |
| 주기 | 1초 (오디오가 흐를 때만; 2초 조용하면 자동 중단) |
| 페이로드 | `{"type":"lufs","momentary":-23.4,"shortTerm":-21.0,"integrated":-22.6,"ts":1747031287123}` |

`-inf` 인 값은 `null` 로 옵니다. `type` 이 `"lufs"` 가 아닌 패킷은 무시합니다.

---

## 처음 한 번: 빌드 환경 준비

이 폴더에는 앱 소스(`lib/`, `pubspec.yaml`)만 들어 있습니다. 플랫폼
스캐폴딩(android/ios)은 Flutter SDK 로 한 번 생성하면 됩니다.

1. **Flutter SDK 설치** — <https://docs.flutter.dev/get-started/install/windows>
   설치 후 새 터미널에서 확인:
   ```powershell
   flutter --version
   flutter doctor
   ```

2. **플랫폼 폴더 생성** — 이 폴더(`lufs_monitor/`) 안에서 실행하세요.
   기존 `pubspec.yaml` 과 `lib/` 는 그대로 두고 android/ 등 누락된 파일만
   채웁니다.
   ```powershell
   flutter create --org com.lufs --platforms=android .
   ```
   (iOS 도 쓰려면 `--platforms=android,ios`. 단 iOS 빌드/배포는 Mac 필요.)

3. **인터넷 권한 추가** — `android/app/src/main/AndroidManifest.xml` 의
   `<manifest>` 바로 아래(= `<application>` 위)에 한 줄 추가:
   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   ```
   (UDP 소켓 bind 에 필요. 브로드캐스트 수신에는 별도 권한이 없습니다.)

4. **패키지 받기 / 실행**
   ```powershell
   flutter pub get
   flutter run            # USB 디버깅 켠 폰을 연결한 상태
   ```

### APK 로 폰에 바로 설치하고 싶다면
```powershell
flutter build apk --release
# 결과물: build/app/outputs/flutter-apk/app-release.apk 를 폰으로 옮겨 설치
```

---

## 동작 확인 체크리스트

1. PC 의 DAW/Standalone 에서 플러그인을 켜고 **오디오를 재생**합니다.
   (정지 상태면 플러그인이 송신을 멈춥니다.)
2. 같은 WiFi 에서 `pwsh ../udp_listen.ps1` 로 PC 자신이 받는지 먼저 확인.
3. 폰 앱을 실행 → 상단이 **수신 중(초록)** 으로 바뀌고 값이 갱신되면 성공.

### 값이 안 들어올 때
- **방화벽**: PC 의 Windows Defender Firewall → 인바운드에서 `UDP 49152`
  허용. (송신은 PC, 수신도 PC 테스트 시 영향)
- **다른 서브넷/게스트 WiFi**: 폰과 PC 가 같은 SSID·같은 서브넷인지 확인.
  일부 공유기의 "게스트망 격리(AP isolation)" 가 켜져 있으면 차단됩니다.
- **안드로이드 브로드캐스트 필터링**: 일부 기기는 절전을 위해 브로드캐스트
  패킷을 버립니다. 이때는 아래 **MulticastLock** 을 추가하세요.

---

## (선택) 안드로이드 MulticastLock 추가

대부분 기기는 락 없이도 받지만, 안 들어오면 WifiManager 의
MulticastLock 을 잡아야 합니다. 앱 코드는 `MethodChannel('lufs/multicast')`
를 호출하도록 이미 작성돼 있고, 네이티브가 없으면 조용히 건너뜁니다.
아래 Kotlin 만 추가하면 활성화됩니다.

`android/app/src/main/kotlin/<...>/MainActivity.kt` 를 다음으로 교체
(`package` 줄은 생성된 파일의 것을 유지):

```kotlin
package io.github.suhyeonppark.lmpm // ← 생성된 파일의 package 그대로 두세요

import android.net.wifi.WifiManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var lock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lufs/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        if (lock == null) {
                            val wifi = applicationContext
                                .getSystemService(Context.WIFI_SERVICE) as WifiManager
                            lock = wifi.createMulticastLock("lufs").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(true)
                    }
                    "release" -> { lock?.release(); lock = null; result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }
}
```

그리고 `AndroidManifest.xml` 에 권한 추가:
```xml
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

---

## 파일 구성

| 파일 | 역할 | 
| --- | --- |
| `lib/lufs_listener.dart` | UDP 49152 수신 · JSON 파싱 · `LufsReading` 스트림 |
| `lib/main.dart` | 다크 테마 UI · 연결 상태 판정 · 값 표시 |
| `pubspec.yaml` | 외부 의존성 없음 (dart:io 만 사용) |
