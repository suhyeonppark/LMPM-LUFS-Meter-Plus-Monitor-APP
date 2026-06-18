import AVFoundation
import AVKit
import Flutter
import UIKit

final class LufsPipPlugin: NSObject, FlutterPlugin {
  private static var shared: LufsPipPlugin?

  private let channel: FlutterMethodChannel
  private var pipRenderer: AnyObject?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lufs/pip", binaryMessenger: registrar.messenger())
    let instance = LufsPipPlugin(channel: channel)
    shared = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    if #available(iOS 15.0, *) {
      pipRenderer = LufsPipRenderer(channel: channel)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *), let renderer = pipRenderer as? LufsPipRenderer else {
      result(call.method == "isSupported" ? false : nil)
      return
    }

    switch call.method {
    case "isSupported":
      result(renderer.isSupported)
    case "enter":
      result(renderer.start())
    case "updateReading":
      renderer.updateReading(call.arguments as? [String: Any])
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

@available(iOS 15.0, *)
private final class LufsPipRenderer: NSObject,
  AVPictureInPictureControllerDelegate,
  AVPictureInPictureSampleBufferPlaybackDelegate
{
  private let channel: FlutterMethodChannel
  private let displayLayer = AVSampleBufferDisplayLayer()
  private var pipController: AVPictureInPictureController?
  private var hostView: UIView?
  private var timer: Timer?
  private var timebase: CMTimebase?
  private var frameIndex: Int64 = 0

  private var momentary: Double?
  private var shortTerm: Double?
  private var integrated: Double?

  private let renderSize = CGSize(width: 540, height: 360)

  var isSupported: Bool {
    AVPictureInPictureController.isPictureInPictureSupported()
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    configure()
  }

  func updateReading(_ args: [String: Any]?) {
    momentary = value(from: args?["momentary"])
    shortTerm = value(from: args?["shortTerm"])
    integrated = value(from: args?["integrated"])
  }

  func start() -> [String: Bool] {
    if Thread.isMainThread {
      return startOnMainThread()
    }
    DispatchQueue.main.async { self.startOnMainThread() }
    return currentState()
  }

  private func configure() {
    displayLayer.videoGravity = .resizeAspect
    displayLayer.backgroundColor = UIColor(red: 0.067, green: 0.075, blue: 0.086, alpha: 1).cgColor
    configureTimebase()

    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    controller.requiresLinearPlayback = true
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    pipController = controller
  }

  @discardableResult
  private func startOnMainThread() -> [String: Bool] {
    activateAudioSession()
    ensureHostView()
    startTimer()
    let state = currentState()

    // isPictureInPicturePossible often flips true only after the layer is attached
    // and at least one sample buffer has been rendered.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self, let controller = self.pipController else { return }
      let possible = controller.isPictureInPicturePossible
      if possible && !controller.isPictureInPictureActive {
        controller.startPictureInPicture()
      }
    }
    return state
  }

  private func currentState() -> [String: Bool] {
    [
      "supported": AVPictureInPictureController.isPictureInPictureSupported(),
      "possible": pipController?.isPictureInPicturePossible ?? false,
      "active": pipController?.isPictureInPictureActive ?? false,
    ]
  }

  private func configureTimebase() {
    var newTimebase: CMTimebase?
    CMTimebaseCreateWithSourceClock(
      allocator: kCFAllocatorDefault,
      sourceClock: CMClockGetHostTimeClock(),
      timebaseOut: &newTimebase
    )
    guard let newTimebase else { return }
    CMTimebaseSetTime(newTimebase, time: .zero)
    CMTimebaseSetRate(newTimebase, rate: 1.0)
    displayLayer.controlTimebase = newTimebase
    timebase = newTimebase
  }

  private func ensureHostView() {
    if hostView != nil { return }

    let view = UIView(frame: CGRect(x: 1, y: 1, width: 2, height: 2))
    view.alpha = 0.01
    view.isUserInteractionEnabled = false
    view.clipsToBounds = true
    displayLayer.frame = view.bounds
    view.layer.addSublayer(displayLayer)
    hostView = view

    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    keyWindow?.rootViewController?.view.addSubview(view)
  }

  private func startTimer() {
    if timer != nil { return }
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.renderFrame()
    }
    RunLoop.main.add(timer!, forMode: .common)
  }

  private func activateAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // PiP 지원 여부는 기기/시뮬레이터 상태에 따라 달라질 수 있어 실패해도 앱은 계속 둔다.
    }
  }

  private func renderFrame() {
    if displayLayer.status == .failed {
      NSLog("LUFS PiP display layer failed: %@", String(describing: displayLayer.error))
      displayLayer.flush()
    }
    guard let sampleBuffer = makeSampleBuffer() else { return }
    displayLayer.enqueue(sampleBuffer)
  }

  private func makeSampleBuffer() -> CMSampleBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]

    CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(renderSize.width),
      Int(renderSize.height),
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard let pixelBuffer else { return nil }

    draw(into: pixelBuffer)

    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )
    guard let formatDescription else { return nil }

    frameIndex += 1
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 2),
      presentationTimeStamp: CMTime(value: frameIndex, timescale: 2),
      decodeTimeStamp: .invalid
    )

    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      dataReady: true,
      makeDataReadyCallback: nil,
      refcon: nil,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    if let sampleBuffer {
      if let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: true
      ), CFArrayGetCount(attachments) > 0 {
        let attachment = unsafeBitCast(
          CFArrayGetValueAtIndex(attachments, 0),
          to: CFMutableDictionary.self
        )
        CFDictionarySetValue(
          attachment,
          Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
          Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
      }
    }
    return sampleBuffer
  }

  private func draw(into pixelBuffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard
      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
      let context = CGContext(
        data: baseAddress,
        width: Int(renderSize.width),
        height: Int(renderSize.height),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
          CGImageAlphaInfo.premultipliedFirst.rawValue
      )
    else { return }

    context.setFillColor(UIColor(red: 0.067, green: 0.075, blue: 0.086, alpha: 1).cgColor)
    context.fill(CGRect(origin: .zero, size: renderSize))

    // Core Graphics 좌표계(원점=좌하단)를 UIKit 좌표계(원점=좌상단)로 뒤집기
    context.translateBy(x: 0, y: renderSize.height)
    context.scaleBy(x: 1, y: -1)

    UIGraphicsPushContext(context)
    drawText()
    UIGraphicsPopContext()
  }

  private func drawText() {
    let white = UIColor.white
    let muted = UIColor(red: 0.72, green: 0.75, blue: 0.78, alpha: 1)
    let dim = UIColor(red: 0.50, green: 0.54, blue: 0.59, alpha: 1)

    let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 104, weight: .light)
    let unitFont = UIFont.systemFont(ofSize: 26, weight: .medium)
    let labelFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
    let miniFont = UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .regular)

    draw(
      "INTEGRATED",
      rect: CGRect(x: 0, y: 42, width: renderSize.width, height: 28),
      attributes: [
        .font: labelFont,
        .foregroundColor: dim,
        .kern: 6,
        .paragraphStyle: centeredParagraph(),
      ]
    )

    let integratedText = format(integrated)
    let valueAttrs: [NSAttributedString.Key: Any] = [
      .font: valueFont,
      .foregroundColor: white,
    ]
    let unitAttrs: [NSAttributedString.Key: Any] = [
      .font: unitFont,
      .foregroundColor: muted,
    ]
    let valueWidth = (integratedText as NSString).size(withAttributes: valueAttrs).width
    let unitWidth = ("LUFS" as NSString).size(withAttributes: unitAttrs).width
    let totalWidth = valueWidth + 18 + unitWidth
    let startX = (renderSize.width - totalWidth) / 2

    draw(
      integratedText,
      rect: CGRect(x: startX, y: 92, width: valueWidth, height: 116),
      attributes: valueAttrs
    )
    draw(
      "LUFS",
      rect: CGRect(x: startX + valueWidth + 18, y: 148, width: unitWidth + 4, height: 34),
      attributes: unitAttrs
    )

    drawMini(label: "M", value: momentary, x: 92, color: muted, labelFont: labelFont, valueFont: miniFont)
    drawMini(label: "S", value: shortTerm, x: 302, color: muted, labelFont: labelFont, valueFont: miniFont)
  }

  private func drawMini(
    label: String,
    value: Double?,
    x: CGFloat,
    color: UIColor,
    labelFont: UIFont,
    valueFont: UIFont
  ) {
    draw(
      label,
      rect: CGRect(x: x, y: 245, width: 24, height: 30),
      attributes: [
        .font: labelFont,
        .foregroundColor: color.withAlphaComponent(0.7),
        .kern: 1,
      ]
    )
    draw(
      format(value),
      rect: CGRect(x: x + 34, y: 232, width: 132, height: 48),
      attributes: [
        .font: valueFont,
        .foregroundColor: color,
      ]
    )
  }

  private func draw(_ text: String, rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
    (text as NSString).draw(in: rect, withAttributes: attributes)
  }

  private func centeredParagraph() -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    return style
  }

  private func value(from raw: Any?) -> Double? {
    if let value = raw as? Double { return value.isFinite ? value : nil }
    if let value = raw as? NSNumber {
      let double = value.doubleValue
      return double.isFinite ? double : nil
    }
    return nil
  }

  private func format(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "-" }
    return String(format: "%.1f", value)
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    NSLog("LUFS PiP did start")
    channel.invokeMethod("pipModeChanged", arguments: true)
    // PiP 시작 후 앱을 백그라운드로 전환
    DispatchQueue.main.async {
      UIApplication.shared.perform(NSSelectorFromString("suspend"))
    }
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    NSLog("LUFS PiP did stop")
    channel.invokeMethod("pipModeChanged", arguments: false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    NSLog("LUFS PiP failed to start: %@", error.localizedDescription)
    channel.invokeMethod("pipModeChanged", arguments: false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {}

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    CMTimeRange(start: .zero, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
}
