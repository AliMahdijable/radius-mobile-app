import CoreBluetooth
import Flutter
import UIKit

/// «طابعة الوصولات» على الآيفون (٩ نوفمبر): طابعات الكاشير الحراريّة التي تدعم BLE. الآيفون لا يفتح البلوتوث
/// «المعتاد» (SPP) للتطبيقات إلّا لأجهزة MFi، فالطابعات بالبلوتوث المعتاد وحده لا تُرى هنا (أندرويد يراها).
///
/// القناة نفسها التي يكلّمها أندرويد (ReceiptPrinterChannel.kt) — btState · btScan · btConnect · btWrite · btRead ·
/// btClose · btSettings — ومنطق الوصل كلّه في دارت. مدير البلوتوث يُنشأ أوّل مرّةٍ يُطلب، فسؤال إذن البلوتوث يظهر
/// حين يختار المدير «طابعة بلوتوث» لا عند فتح التطبيق. كلّ شيءٍ بنداءاتٍ راجعة على الخيط الرئيس — لا انتظار يجمّده.
final class ReceiptPrinterBle: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  static let channelName = "com.mysvcs.rad_mysvcs/receipt_printer"
  private static var shared: ReceiptPrinterBle?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let me = ReceiptPrinterBle()
    shared = me
    channel.setMethodCallHandler { call, result in me.handle(call, result) }
  }

  /// قنوات الطابعات المعروفة لـ«الكتابة» (الأولى أوّلاً) — وإلّا أوّل قناةٍ تقبل الكتابة خارج خدمات النظام.
  private static let preferredWrite: [CBUUID] = [
    CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F"),
    CBUUID(string: "2AF1"),
    CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3"),
    CBUUID(string: "FF02"),
    CBUUID(string: "FFE1"),
  ]
  private static let printerServices: Set<CBUUID> = [
    CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"),
    CBUUID(string: "18F0"),
    CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455"),
    CBUUID(string: "FF00"),
    CBUUID(string: "FFE0"),
  ]
  /// خدمات النظام (الاسم، الصانع، البطّاريّة) لا تُطبع عليها.
  private static let ignoredServices: Set<CBUUID> = [
    CBUUID(string: "1800"), CBUUID(string: "1801"), CBUUID(string: "180A"), CBUUID(string: "180F"),
  ]

  private var central: CBCentralManager?
  private var stateWaiters: [() -> Void] = []

  private struct Found {
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    let printer: Bool
  }

  private var found: [UUID: Found] = [:]
  private var scanResult: FlutterResult?
  private var scanTimer: Timer?

  private var peripheral: CBPeripheral?
  private var writeChar: CBCharacteristic?
  private var notifyChar: CBCharacteristic?
  private var connectResult: FlutterResult?
  private var connectTimer: Timer?
  private var pendingServices = 0

  /// رقم الاتّصال: يزيد مع كلّ btConnect. انقطاعٌ يصل متأخّراً عن اتّصالٍ أُغلق (الطابعة نفسها، إعادة طباعةٍ بعد لحظة)
  /// لا يمسّ الاتّصال الجديد: الانقطاع يخصّ الاتّصال الذي قال CoreBluetooth إنّه قام ([upLink]).
  private var link = 0
  private var upLink = -1

  private var writeQueue: [Data] = []
  private var writeResult: FlutterResult?
  private var writeType: CBCharacteristicWriteType = .withResponse

  private var rx = Data()
  private var readResult: FlutterResult?
  private var readTimer: Timer?
  private var readMax = 64

  // MARK: - Channel

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "btState":
      whenStateKnown { result(self.stateMap()) }
    case "btPaired":
      result([])
    case "btScan":
      scan(timeoutMs: args["timeoutMs"] as? Int ?? 8000, result)
    case "btConnect":
      connect(id: args["id"] as? String ?? "", timeoutMs: args["timeoutMs"] as? Int ?? 12000, result)
    case "btWrite":
      write((args["data"] as? FlutterStandardTypedData)?.data ?? Data(), result)
    case "btRead":
      read(timeoutMs: args["timeoutMs"] as? Int ?? 500, max: args["max"] as? Int ?? 64, result)
    case "btClose":
      close()
      result(true)
    case "btSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(true)
    case "builtinInfo":
      result(["available": false, "vendor": ""])
    case "builtinPrint":
      result(FlutterError(code: "unsupported", message: "no built-in printer on iPhone", details: nil))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - State

  private func manager() -> CBCentralManager {
    if let c = central { return c }
    let c = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    central = c
    return c
  }

  /// [then] حين تُعرف حال البلوتوث — أو بعد ٣٠ ثانية (نافذة الإذن قد تكون مفتوحة).
  private func whenStateKnown(_ then: @escaping () -> Void) {
    let c = manager()
    if c.state != .unknown && c.state != .resetting {
      then()
      return
    }
    stateWaiters.append(then)
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.flushStateWaiters() }
  }

  private func flushStateWaiters() {
    let waiting = stateWaiters
    stateWaiters = []
    waiting.forEach { $0() }
  }

  private func stateMap() -> [String: Any] {
    let s = manager().state
    let auth = CBManager.authorization
    return [
      "supported": s != .unsupported,
      "enabled": s == .poweredOn,
      "authorized": s != .unauthorized && auth != .denied && auth != .restricted,
    ]
  }

  private func stateError(_ s: CBManagerState) -> FlutterError {
    switch s {
    case .unauthorized: return FlutterError(code: "permission", message: "bluetooth not allowed", details: nil)
    case .unsupported: return FlutterError(code: "unsupported", message: "no bluetooth", details: nil)
    default: return FlutterError(code: "off", message: "bluetooth is off", details: nil)
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state != .unknown && central.state != .resetting { flushStateWaiters() }
    if central.state != .poweredOn && central.state != .unknown {
      // انطفأ البلوتوث أو سُحب الإذن أثناء العمل.
      let err = stateError(central.state)
      finishScan()
      finishConnect(err)
      failWrite(err)
      finishRead()
      resetLink()
    }
  }

  // MARK: - Scan

  private func scan(timeoutMs: Int, _ result: @escaping FlutterResult) {
    whenStateKnown { [self] in
      let c = self.manager()
      guard c.state == .poweredOn else {
        result(self.stateError(c.state))
        return
      }
      if self.scanResult != nil { self.finishScan() }
      self.found = [:]
      self.scanResult = result
      c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
      self.scanTimer = Timer.scheduledTimer(withTimeInterval: Double(max(1000, timeoutMs)) / 1000, repeats: false) {
        [weak self] _ in self?.finishScan()
      }
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    let name = ((advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    // بلا اسم = سمّاعاتٌ وأجهزةٌ لا تُختار — الطابعات تُعلن اسمها.
    if name.isEmpty { return }
    let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    let lower = name.lowercased()
    let printer = services.contains { Self.printerServices.contains($0) }
      || ["print", "pos", "mpt", "mtp", "xp-", "rpp", "pt-", "inner"].contains { lower.contains($0) }
    let rssi = RSSI.intValue == 127 ? -999 : RSSI.intValue
    found[peripheral.identifier] = Found(peripheral: peripheral, name: name, rssi: rssi, printer: printer)
  }

  private func finishScan() {
    scanTimer?.invalidate()
    scanTimer = nil
    if central?.isScanning == true { central?.stopScan() }
    guard let r = scanResult else { return }
    scanResult = nil
    r(found.values.map { f -> [String: Any] in
      ["id": f.peripheral.identifier.uuidString, "name": f.name, "rssi": f.rssi, "printer": f.printer]
    })
  }

  // MARK: - Connect

  private func connect(id: String, timeoutMs: Int, _ result: @escaping FlutterResult) {
    whenStateKnown { [self] in
      let c = self.manager()
      guard c.state == .poweredOn else {
        result(self.stateError(c.state))
        return
      }
      guard let uuid = UUID(uuidString: id) else {
        result(FlutterError(code: "not_found", message: "bad printer id", details: nil))
        return
      }
      self.close()
      guard let p = self.found[uuid]?.peripheral ?? c.retrievePeripherals(withIdentifiers: [uuid]).first else {
        result(FlutterError(code: "not_found", message: "printer not known to this iPhone", details: nil))
        return
      }
      self.link &+= 1
      self.peripheral = p
      p.delegate = self
      self.connectResult = result
      self.connectTimer = Timer.scheduledTimer(withTimeInterval: Double(max(2000, timeoutMs)) / 1000, repeats: false) {
        [weak self] _ in
        self?.finishConnect(FlutterError(code: "timeout", message: "connect timeout", details: nil))
        self?.close()
      }
      c.connect(p, options: nil)
    }
  }

  private func finishConnect(_ value: Any) {
    connectTimer?.invalidate()
    connectTimer = nil
    guard let r = connectResult else { return }
    connectResult = nil
    r(value)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard peripheral == self.peripheral else { return }
    upLink = link
    peripheral.discoverServices(nil)
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    // فشلُ اتّصالٍ لم يقم بعد — ما قام (upLink) ينقطع بـdidDisconnect لا بهذا.
    guard peripheral == self.peripheral, upLink != link else { return }
    finishConnect(FlutterError(code: "connect_failed", message: error?.localizedDescription, details: nil))
    resetLink()
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    // انقطاعٌ لاتّصالٍ لم يقم بعد = تأكيد إغلاق اتّصالٍ سابقٍ بالطابعة نفسها وصل متأخّراً — ليس لهذا الاتّصال.
    guard peripheral == self.peripheral, upLink == link else { return }
    let err = FlutterError(code: "io", message: error?.localizedDescription ?? "disconnected", details: nil)
    finishConnect(FlutterError(code: "connect_failed", message: err.message, details: nil))
    failWrite(err)
    finishRead()
    resetLink()
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    let services = (peripheral.services ?? []).filter { !Self.ignoredServices.contains($0.uuid) }
    if services.isEmpty {
      finishConnect(FlutterError(code: "no_write", message: "no printing service", details: nil))
      close()
      return
    }
    pendingServices = services.count
    services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    pendingServices -= 1
    if pendingServices > 0 { return }
    let all = (peripheral.services ?? [])
      .filter { !Self.ignoredServices.contains($0.uuid) }
      .flatMap { $0.characteristics ?? [] }
    let writable = all.filter { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
    let preferred = Self.preferredWrite.lazy.compactMap { u in writable.first { $0.uuid == u } }.first
    guard let w = preferred ?? writable.first else {
      finishConnect(FlutterError(code: "no_write", message: "no writable characteristic", details: nil))
      close()
      return
    }
    writeChar = w
    writeType = w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
    // ردود الطابعة (أسئلة الحالة) من قناة «إشعار» في الخدمة نفسها إن وُجدت.
    if let n = w.service?.characteristics?.first(where: {
      $0.properties.contains(.notify) || $0.properties.contains(.indicate)
    }) {
      notifyChar = n
      peripheral.setNotifyValue(true, for: n)
    }
    finishConnect(true)
  }

  // MARK: - Write

  private func write(_ data: Data, _ result: @escaping FlutterResult) {
    guard let p = peripheral, writeChar != nil, p.state == .connected else {
      result(FlutterError(code: "io", message: "not connected", details: nil))
      return
    }
    if writeResult != nil {
      result(FlutterError(code: "busy", message: "write in progress", details: nil))
      return
    }
    // بقدر الاتّصال (MTU − 3) لنوعي الكتابة، وبسقفٍ لطيف على ذاكرة الطابعات الصغيرة. ⚠️ لا «طول الكتابة بردّ»:
    // يعطي ٥١٢ (كتابةً طويلة بأجزاء) فيصير كلّ جزءٍ «Prepare + Execute Write» — طابعاتٌ لا تعرفها تردّ خطأً ولا يُطبع شيء.
    // جزءٌ بقدر الـMTU يذهب «Write Request» واحداً.
    let size = max(20, min(p.maximumWriteValueLength(for: .withoutResponse), 180))
    var parts: [Data] = []
    var off = 0
    while off < data.count {
      let end = min(off + size, data.count)
      parts.append(data.subdata(in: off..<end))
      off = end
    }
    writeQueue = parts
    writeResult = result
    pump()
  }

  private func pump() {
    guard let p = peripheral, let w = writeChar else { return }
    if writeType == .withoutResponse {
      while !writeQueue.isEmpty && p.canSendWriteWithoutResponse {
        p.writeValue(writeQueue.removeFirst(), for: w, type: .withoutResponse)
      }
      if writeQueue.isEmpty { finishWrite() }
      // وإلّا: البقيّة حين peripheralIsReady.
    } else {
      if writeQueue.isEmpty {
        finishWrite()
        return
      }
      p.writeValue(writeQueue.removeFirst(), for: w, type: .withResponse)
    }
  }

  private func finishWrite() {
    guard let r = writeResult else { return }
    writeResult = nil
    r(true)
  }

  private func failWrite(_ err: FlutterError) {
    writeQueue = []
    guard let r = writeResult else { return }
    writeResult = nil
    r(err)
  }

  func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    if writeResult != nil { pump() }
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    if let e = error {
      failWrite(FlutterError(code: "io", message: e.localizedDescription, details: nil))
      return
    }
    if writeResult != nil { pump() }
  }

  // MARK: - Read

  private func read(timeoutMs: Int, max: Int, _ result: @escaping FlutterResult) {
    readMax = Swift.max(1, max)
    if !rx.isEmpty {
      result(FlutterStandardTypedData(bytes: takeRx()))
      return
    }
    guard notifyChar != nil, peripheral?.state == .connected else {
      // لا قناة نسمع منها الطابعة: صامتة.
      result(FlutterStandardTypedData(bytes: Data()))
      return
    }
    finishRead()
    readResult = result
    readTimer = Timer.scheduledTimer(withTimeInterval: Double(Swift.max(10, timeoutMs)) / 1000, repeats: false) {
      [weak self] _ in self?.finishRead()
    }
  }

  private func takeRx() -> Data {
    let n = Swift.min(readMax, rx.count)
    let out = Data(rx.prefix(n))
    rx = Data(rx.dropFirst(n))
    return out
  }

  private func finishRead() {
    readTimer?.invalidate()
    readTimer = nil
    guard let r = readResult else { return }
    readResult = nil
    r(FlutterStandardTypedData(bytes: takeRx()))
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic == notifyChar, let v = characteristic.value, !v.isEmpty else { return }
    rx.append(v)
    if rx.count > 4096 { rx = Data(rx.suffix(4096)) }
    if readResult != nil {
      // ردّ الحالة بايتٌ واحد عادةً — لحظةٌ لما قد يلحقه ثمّ يُعاد.
      readTimer?.invalidate()
      readTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in self?.finishRead() }
    }
  }

  // MARK: - Close

  /// يُغلق الاتّصال، ويُجيب الآن — مرّةً واحدة — كلَّ نداءٍ ينتظر ردّه منه: كتابةٌ لم تكتمل (مهلة دارت ٤٥ ث على طابعةٍ عالقة،
  /// أو تطبيقٌ عُلّق أثناء الطباعة) كانت تبقى «جاريةً» فيُردّ كلّ وصلٍ بعدها بـ«busy» حتى يُطفأ البلوتوث؛ واتّصالٌ ينتظر
  /// كان يُترك بلا ردّ حين يبدأ غيره.
  private func close() {
    let closed = FlutterError(code: "io", message: "closed", details: nil)
    finishConnect(closed)
    failWrite(closed)
    finishRead()
    if let p = peripheral, let c = central {
      if let n = notifyChar, p.state == .connected { p.setNotifyValue(false, for: n) }
      c.cancelPeripheralConnection(p)
    }
    resetLink()
  }

  private func resetLink() {
    connectTimer?.invalidate()
    connectTimer = nil
    upLink = -1
    peripheral?.delegate = nil
    peripheral = nil
    writeChar = nil
    notifyChar = nil
    writeQueue = []
    rx = Data()
    pendingServices = 0
  }
}
