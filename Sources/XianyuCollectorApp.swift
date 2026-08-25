import SwiftUI
import Security
import UIKit


// =====================================================
// MARK: - App
// =====================================================

@main
struct XianyuCollectorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}


// =====================================================
// MARK: - 配置
// =====================================================

enum AppConfig {

    static let apiBaseURL =
        "https://api.529059096.xyz"

    // 目前开发阶段继续使用现有 Token。
    // 最终上线前一定要更换。
    static let apiToken =
        "请填入你当前正在使用的API_TOKEN"

    static let appVersion =
        "0.3.0"

    static let deviceName =
        "闲鱼采集机"

    static let heartbeatInterval:
        TimeInterval = 30 * 60

    static let uploadRetryInterval:
        TimeInterval = 60
}


// =====================================================
// MARK: - Keychain
// =====================================================

enum KeychainManager {

    private static let service =
        "com.xianyu.collector"

    private static let deviceIDAccount =
        "device_id"

    static func getDeviceID() -> String? {

        let query:
            [String: Any] = [

            kSecClass as String:
                kSecClassGenericPassword,

            kSecAttrService as String:
                service,

            kSecAttrAccount as String:
                deviceIDAccount,

            kSecReturnData as String:
                true,

            kSecMatchLimit as String:
                kSecMatchLimitOne
        ]

        var result:
            AnyObject?

        let status =
            SecItemCopyMatching(
                query as CFDictionary,
                &result
            )

        guard status == errSecSuccess,
              let data =
                result as? Data,
              let value =
                String(
                    data: data,
                    encoding: .utf8
                )
        else {
            return nil
        }

        return value
    }


    static func saveDeviceID(
        _ deviceID: String
    ) -> Bool {

        guard let data =
            deviceID.data(
                using: .utf8
            )
        else {
            return false
        }

        let query:
            [String: Any] = [

            kSecClass as String:
                kSecClassGenericPassword,

            kSecAttrService as String:
                service,

            kSecAttrAccount as String:
                deviceIDAccount
        ]

        let attributes:
            [String: Any] = [

            kSecValueData as String:
                data
        ]

        let updateStatus =
            SecItemUpdate(
                query as CFDictionary,
                attributes as CFDictionary
            )

        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {

            var addQuery =
                query

            addQuery[
                kSecValueData as String
            ] = data

            let addStatus =
                SecItemAdd(
                    addQuery as CFDictionary,
                    nil
                )

            return addStatus ==
                errSecSuccess
        }

        return false
    }


    static func getOrCreateDeviceID()
        -> String {

        if let existing =
            getDeviceID() {

            return existing
        }

        let newID =
            UUID().uuidString

        _ = saveDeviceID(
            newID
        )

        return newID
    }
}


// =====================================================
// MARK: - 数据模型
// =====================================================

struct UploadPayload: Codable {

    let deviceID: String
    let eventID: String
    let capturedAt: String
    let source: String
    let payload: [String: String]


    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case eventID = "event_id"
        case capturedAt = "captured_at"
        case source
        case payload
    }
}


// =====================================================
// MARK: - 本地队列
// =====================================================

final class UploadQueue {

    static let shared =
        UploadQueue()

    private let fileManager =
        FileManager.default

    private let queueDirectoryName =
        "UploadQueue"

    private var queueDirectory:
        URL {

        let base =
            fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]

        let directory =
            base.appendingPathComponent(
                queueDirectoryName,
                isDirectory: true
            )

        if !fileManager.fileExists(
            atPath: directory.path
        ) {

            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        return directory
    }


    private let encoder =
        JSONEncoder()


    private let decoder =
        JSONDecoder()


    // -------------------------------------------------
    // 添加任务
    // -------------------------------------------------

    func enqueue(
        _ item: UploadPayload
    ) {

        let fileName =
            "\(item.eventID).json"

        let fileURL =
            queueDirectory
                .appendingPathComponent(
                    fileName
                )

        do {

            let data =
                try encoder.encode(
                    item
                )

            try data.write(
                to: fileURL,
                options: [
                    .atomic
                ]

            )

        } catch {

            print(
                "Queue save failed:",
                error
            )
        }
    }


    // -------------------------------------------------
    // 获取全部任务
    // -------------------------------------------------

    func allItems()
        -> [UploadPayload] {

        guard let files =
            try? fileManager.contentsOfDirectory(
                at: queueDirectory,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }

        var result:
            [UploadPayload] = []

        for file in files
        where file.pathExtension == "json" {

            do {

                let data =
                    try Data(
                        contentsOf: file
                    )

                let item =
                    try decoder.decode(
                        UploadPayload.self,
                        from: data
                    )

                result.append(
                    item
                )

            } catch {

                print(
                    "Queue decode failed:",
                    error
                )
            }
        }

        return result.sorted {
            $0.eventID <
                $1.eventID
        }
    }


    // -------------------------------------------------
    // 删除任务
    // -------------------------------------------------

    func remove(
        _ item: UploadPayload
    ) {

        let fileURL =
            queueDirectory
                .appendingPathComponent(
                    "\(item.eventID).json"
                )

        try? fileManager.removeItem(
            at: fileURL
        )
    }


    // -------------------------------------------------
    // 当前队列数量
    // -------------------------------------------------

    func count() -> Int {

        guard let files =
            try? fileManager.contentsOfDirectory(
                at: queueDirectory,
                includingPropertiesForKeys: nil
            )
        else {
            return 0
        }

        return files.filter {
            $0.pathExtension == "json"
        }.count
    }
}


// =====================================================
// MARK: - API Client
// =====================================================

final class APIClient {

    static let shared =
        APIClient()


    private let session:
        URLSession


    private init() {

        let configuration =
            URLSessionConfiguration.default

        configuration.timeoutIntervalForRequest =
            30

        configuration.timeoutIntervalForResource =
            60

        session =
            URLSession(
                configuration:
                    configuration
            )
    }


    // -------------------------------------------------
    // Authorization
    // -------------------------------------------------

    private func addAuthHeader(
        to request: inout URLRequest
    ) {

        request.setValue(
            "Bearer \(AppConfig.apiToken)",
            forHTTPHeaderField:
                "Authorization"
        )
    }


    // -------------------------------------------------
    // Heartbeat
    // -------------------------------------------------

    func heartbeat(
        completion:
            @escaping (Result<
                String,
                Error
            >) -> Void
    ) {

        guard let url =
            URL(
                string:
                    "\(AppConfig.apiBaseURL)/v1/devices/heartbeat"
            )
        else {

            completion(
                .failure(
                    APIError.invalidURL
                )
            )

            return
        }


        var request =
            URLRequest(
                url: url
            )

        request.httpMethod =
            "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )

        addAuthHeader(
            to: &request
        )


        let deviceID =
            KeychainManager
                .getOrCreateDeviceID()


        let network =
            NetworkMonitor
                .shared
                .currentNetworkType()


        let battery =
            Int(
                UIDevice.current
                    .batteryLevel * 100
            )


        UIDevice.current
            .isBatteryMonitoringEnabled =
            true


        let actualBattery =
            UIDevice.current
                .batteryLevel


        let batteryValue:
            Int? = (

            actualBattery >= 0
            ? Int(
                actualBattery * 100
            )
            : nil

        )


        let body:
            [String: Any] = [

            "device_id":
                deviceID,

            "device_name":
                AppConfig.deviceName,

            "app_version":
                AppConfig.appVersion,

            "network":
                network,

            "battery":
                batteryValue as Any
        ]


        do {

            request.httpBody =
                try JSONSerialization.data(
                    withJSONObject:
                        body,
                    options: []
                )

        } catch {

            completion(
                .failure(
                    error
                )
            )

            return
        }


        session.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {

                completion(
                    .failure(
                        error
                    )
                )

                return
            }


            guard let response =
                response as?
                    HTTPURLResponse
            else {

                completion(
                    .failure(
                        APIError.invalidResponse
                    )
                )

                return
            }


            let responseText =
                String(
                    data:
                        data ?? Data(),
                    encoding:
                        .utf8
                ) ?? ""


            if (200...299)
                .contains(
                    response.statusCode
                ) {

                completion(
                    .success(
                        responseText
                    )
                )

            } else {

                completion(
                    .failure(
                        APIError.server(
                            response.statusCode,
                            responseText
                        )
                    )
                )
            }

        }.resume()
    }


    // -------------------------------------------------
    // Upload
    // -------------------------------------------------

    func upload(
        _ item:
            UploadPayload,

        completion:
            @escaping (Result<
                String,
                Error
            >) -> Void
    ) {

        guard let url =
            URL(
                string:
                    "\(AppConfig.apiBaseURL)/v1/metrics"
            )
        else {

            completion(
                .failure(
                    APIError.invalidURL
                )
            )

            return
        }


        var request =
            URLRequest(
                url: url
            )

        request.httpMethod =
            "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )

        addAuthHeader(
            to: &request
        )


        do {

            request.httpBody =
                try JSONEncoder()
                    .encode(
                        item
                    )

        } catch {

            completion(
                .failure(
                    error
                )
            )

            return
        }


        session.dataTask(
            with: request
        ) { data, response, error in

            if let error = error {

                completion(
                    .failure(
                        error
                    )
                )

                return
            }


            guard let response =
                response as?
                    HTTPURLResponse
            else {

                completion(
                    .failure(
                        APIError.invalidResponse
                    )
                )

                return
            }


            let responseText =
                String(
                    data:
                        data ?? Data(),
                    encoding:
                        .utf8
                ) ?? ""


            if (200...299)
                .contains(
                    response.statusCode
                ) {

                completion(
                    .success(
                        responseText
                    )
                )

            } else {

                completion(
                    .failure(
                        APIError.server(
                            response.statusCode,
                            responseText
                        )
                    )
                )
            }

        }.resume()
    }
}


// =====================================================
// MARK: - API Error
// =====================================================

enum APIError:
    LocalizedError {

    case invalidURL
    case invalidResponse
    case server(
        Int,
        String
    )

    var errorDescription:
        String? {

        switch self {

        case .invalidURL:
            return "API URL 无效"

        case .invalidResponse:
            return "服务器响应无效"

        case .server(
            let status,
            let text
        ):
            return
                "服务器 \(status)：\(text)"
        }
    }
}


// =====================================================
// MARK: - 网络状态
// =====================================================

import Network

final class NetworkMonitor {

    static let shared =
        NetworkMonitor()


    private let monitor =
        NWPathMonitor()


    private let queue =
        DispatchQueue(
            label:
                "NetworkMonitor"
        )


    private var currentPath:
        NWPath?


    private init() {

        monitor.pathUpdateHandler = {
            [weak self] path in

            self?.currentPath =
                path
        }


        monitor.start(
            queue: queue
        )
    }


    func currentNetworkType()
        -> String {

        guard let path =
            currentPath
        else {
            return "unknown"
        }


        if path.usesInterfaceType(
            .wifi
        ) {
            return "WiFi"
        }


        if path.usesInterfaceType(
            .cellular
        ) {
            return "5G/4G"
        }


        if path.usesInterfaceType(
            .wiredEthernet
        ) {
            return "Ethernet"
        }


        return "other"
    }
}


// =====================================================
// MARK: - Collector Manager
// =====================================================

final class CollectorManager:
    ObservableObject {

    @Published private(set) var status =
        "初始化中..."


    @Published private(set) var queueCount =
        0


    @Published private(set) var deviceID =
        ""


    private var heartbeatTimer:
        Timer?


    private var retryTimer:
        Timer?


    init() {

        deviceID =
            KeychainManager
                .getOrCreateDeviceID()

        queueCount =
            UploadQueue.shared.count()
    }


    deinit {

        heartbeatTimer?.invalidate()

        retryTimer?.invalidate()
    }


    // -------------------------------------------------
    // 启动
    // -------------------------------------------------

    func start() {

        status =
            "设备初始化完成"


        sendHeartbeat()


        retryPendingUploads()


        heartbeatTimer =
            Timer.scheduledTimer(
                withTimeInterval:
                    AppConfig.heartbeatInterval,
                repeats:
                    true
            ) { [weak self] _ in

                self?.sendHeartbeat()
            }


        retryTimer =
            Timer.scheduledTimer(
                withTimeInterval:
                    AppConfig.uploadRetryInterval,
                repeats:
                    true
            ) { [weak self] _ in

                self?.retryPendingUploads()
            }
    }


    // -------------------------------------------------
    // Heartbeat
    // -------------------------------------------------

    func sendHeartbeat() {

        status =
            "发送心跳..."


        APIClient.shared.heartbeat {
            [weak self] result in

            DispatchQueue.main.async {

                switch result {

                case .success:

                    self?.status =
                        "设备在线"

                case .failure(
                    let error
                ):

                    self?.status =
                        "心跳失败：\(error.localizedDescription)"
                }
            }
        }
    }


    // -------------------------------------------------
    // 测试生成一个数据任务
    // -------------------------------------------------

    func createTestData() {

        let deviceID =
            KeychainManager
                .getOrCreateDeviceID()


        let formatter =
            DateFormatter()

        formatter.dateFormat =
            "yyyy-MM-dd HH:mm:ss"

        formatter.locale =
            Locale(
                identifier:
                    "en_US_POSIX"
            )

        formatter.timeZone =
            TimeZone.current


        let item =
            UploadPayload(

                deviceID:
                    deviceID,

                eventID:
                    UUID().uuidString,

                capturedAt:
                    formatter.string(
                        from:
                            Date()
                    ),

                source:
                    "xianyu",

                payload: [

                    "test":
                        "true",

                    "message":
                        "hello from iPhone V0.3",

                    "network":
                        NetworkMonitor.shared
                            .currentNetworkType()
                ]
            )


        UploadQueue.shared
            .enqueue(
                item
            )


        refreshQueueCount()


        status =
            "测试数据已进入本地队列"


        retryPendingUploads()
    }


    // -------------------------------------------------
    // 上传队列
    // -------------------------------------------------

    func retryPendingUploads() {

        let items =
            UploadQueue.shared.allItems()


        if items.isEmpty {

            refreshQueueCount()

            return
        }


        status =
            "正在上传 \(items.count) 个任务..."


        uploadNext(
            items
        )
    }


    private func uploadNext(
        _ items:
            [UploadPayload]
    ) {

        guard
            let first =
                items.first
        else {

            DispatchQueue.main.async {
                self.refreshQueueCount()
                self.status =
                    "队列已处理"
            }

            return
        }


        APIClient.shared.upload(
            first
        ) { [weak self] result in

            guard let self =
                self
            else {
                return
            }


            switch result {

            case .success:

                UploadQueue.shared
                    .remove(
                        first
                    )

                DispatchQueue.main.async {

                    self.refreshQueueCount()

                    let remaining =
                        items.dropFirst()

                    if remaining.isEmpty {

                        self.status =
                            "上传完成"

                    } else {

                        self.status =
                            "已上传，剩余 \(remaining.count)"
                    }
                }


                self.uploadNext(
                    Array(
                        items.dropFirst()
                    )
                )


            case .failure(
                let error
            ):

                DispatchQueue.main.async {

                    self.refreshQueueCount()

                    self.status =
                        "上传失败，稍后重试：\(error.localizedDescription)"
                }
            }
        }
    }


    // -------------------------------------------------
    // 队列数量
    // -------------------------------------------------

    private func refreshQueueCount() {

        DispatchQueue.main.async {

            self.queueCount =
                UploadQueue.shared.count()
        }
    }
}


// =====================================================
// MARK: - SwiftUI 页面
// =====================================================

struct ContentView:
    View {

    @StateObject private var manager =
        CollectorManager()


    var body: some View {

        ScrollView {

            VStack(
                spacing: 18
            ) {

                Text(
                    "XianyuCollector"
                )
                .font(
                    .title
                )
                .bold()


                Text(
                    "V0.3"
                )
                .font(
                    .subheadline
                )
                .foregroundColor(
                    .secondary
                )


                Divider()


                VStack(
                    alignment:
                        .leading,
                    spacing:
                        8
                ) {

                    Text(
                        "Device ID"
                    )
                    .font(
                        .headline
                    )

                    Text(
                        manager.deviceID
                    )
                    .font(
                        .caption
                    )
                    .textSelection(
                        .enabled
                    )
                }


                VStack(
                    spacing:
                        8
                ) {

                    Text(
                        manager.status
                    )
                    .multilineTextAlignment(
                        .center
                    )

                    Text(
                        "待上传：\(manager.queueCount)"
                    )
                    .foregroundColor(
                        .secondary
                    )
                }


                Button(
                    "立即发送心跳"
                ) {

                    manager.sendHeartbeat()
                }
                .buttonStyle(
                    .borderedProminent
                )


                Button(
                    "创建测试数据"
                ) {

                    manager.createTestData()
                }
                .buttonStyle(
                    .bordered
                )


                Button(
                    "立即重试上传"
                ) {

                    manager.retryPendingUploads()
                }
                .buttonStyle(
                    .bordered
                )
            }
            .padding()
        }
        .onAppear {

            UIDevice.current
                .isBatteryMonitoringEnabled =
                true

            manager.start()
        }
    }
}
