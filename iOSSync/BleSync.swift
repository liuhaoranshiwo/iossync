import Foundation
import CoreBluetooth

/// BLE 直连同步：扫描手表 GATT 服务 → 连接 → 分帧写 JSON
/// 与手表端 BleServer.kt 协议一致：
///   Service A2CF0000-... / Char01 写通道 / Char02 状态 notify
/// 分帧: [seq:1][total:1][payload...]，payload ≤ 180 字节
final class BleSync: NSObject, ObservableObject {
    static let shared = BleSync()

    static let serviceUUID = CBUUID(string: "A2CF0000-6B4D-4A6B-8C9F-5E1D3A7B2C4D")
    static let writeUUID   = CBUUID(string: "A2CF0001-6B4D-4A6B-8C9F-5E1D3A7B2C4D")
    static let statusUUID  = CBUUID(string: "A2CF0002-6B4D-4A6B-8C9F-5E1D3A7B2C4D")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?

    @Published var state = "未连接"
    @Published var connected = false

    private var pendingJSON: Data?
    private var onDone: ((String) -> Void)?
    private var timeoutWork: DispatchWorkItem?

    override private init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// 通过蓝牙发送同步数据
    func send(json: [String: Any], completion: @escaping (String) -> Void) {
        onDone = completion
        pendingJSON = try? JSONSerialization.data(withJSONObject: json)
        guard pendingJSON != nil else {
            completion("数据序列化失败")
            return
        }
        switch central.state {
        case .poweredOn:
            if connected, let p = peripheral {
                state = "发送中…"
                p.discoverServices([Self.serviceUUID])
            } else {
                state = "扫描手表…"
                central.scanForPeripherals(withServices: [Self.serviceUUID])
                armTimeout("没找到手表（检查手表蓝牙已开、且 iOSSync App 已打开）", seconds: 12)
            }
        case .unauthorized:
            completion("蓝牙权限未授权（设置 → 隐私与安全性 → 蓝牙）")
        case .poweredOff:
            completion("iPhone 蓝牙未开启")
        default:
            state = "蓝牙启动中…"
            armTimeout("蓝牙状态异常", seconds: 12)
        }
    }

    private func armTimeout(_ msg: String, seconds: Double) {
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.connected else { return }
            self.central.stopScan()
            self.state = "未连接"
            self.onDone?(msg)
            self.onDone = nil
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func sendPackets() {
        guard let data = pendingJSON,
              let p = peripheral, let ch = writeChar else { return }
        let chunkSize = 180
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        state = "发送中…"
        for (i, chunk) in chunks.enumerated() {
            var packet = Data([UInt8(i), UInt8(chunks.count)])
            packet.append(chunk)
            p.writeValue(packet, for: ch, type: .withResponse)
        }
        armTimeout("发送超时", seconds: 8)
    }
}

extension BleSync: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, pendingJSON != nil, !connected {
            central.scanForPeripherals(withServices: [Self.serviceUUID])
            state = "扫描手表…"
            armTimeout("没找到手表（检查手表蓝牙已开、且 iOSSync App 已打开）", seconds: 12)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        timeoutWork?.cancel()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = "连接中…"
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected = true
        state = "发现服务…"
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connected = false
        state = "未连接"
        onDone?("蓝牙连接失败: \(error?.localizedDescription ?? "未知错误")")
        onDone = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected = false
        writeChar = nil
        statusChar = nil
        if state == "发送中…" || state == "发现服务…" {
            state = "未连接"
        }
    }
}

extension BleSync: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            onDone?("手表服务未找到")
            onDone = nil
            return
        }
        peripheral.discoverCharacteristics([Self.writeUUID, Self.statusUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.writeUUID { writeChar = ch }
            if ch.uuid == Self.statusUUID {
                statusChar = ch
                peripheral.setNotifyValue(true, for: ch)
            }
        }
        if writeChar != nil {
            sendPackets()
        } else {
            onDone?("手表写通道未找到")
            onDone = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            // 订阅失败不阻塞：写入本身有 response 确认
            debugPrint("notify subscribe error: \(e.localizedDescription)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // 手表回执 "OK"
        if characteristic.uuid == Self.statusUUID,
           let v = characteristic.value, String(data: v, encoding: .utf8) == "OK" {
            timeoutWork?.cancel()
            state = "已连接"
            onDone?("蓝牙同步成功")
            onDone = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            timeoutWork?.cancel()
            state = "已连接"
            onDone?("写入失败: \(e.localizedDescription)")
            onDone = nil
        }
    }
}
