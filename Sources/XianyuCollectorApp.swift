import SwiftUI

@main
struct XianyuCollectorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var status = "等待测试"

    var body: some View {
        VStack(spacing: 20) {
            Text("XianyuCollector")
                .font(.title)
                .bold()

            Text("V0.2")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(status)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("测试上传") {
                uploadTestData()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func uploadTestData() {
        DispatchQueue.main.async {
            status = "正在上传..."
        }

        // =====================================================
        // API配置
        // =====================================================

        let apiURL =
            "https://api.529059096.xyz/v1/metrics"

        // 把这里替换成服务器 .env 中的 API_TOKEN。
        //
        // 注意：
        // 这是 V0.2 测试方案。
        // 后续 V0.3 会改为设备独立 Token + Keychain。
        let apiToken =
            "9f8a7c6d5e4b3a2f1c0d9e8f7a6b5c4e"

        guard let url = URL(
            string: apiURL
        ) else {
            updateStatus("API地址错误")
            return
        }

        // =====================================================
        // HTTP Request
        // =====================================================

        var request = URLRequest(
            url: url,
            timeoutInterval: 30
        )

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )

        request.setValue(
            "Bearer \(apiToken)",
            forHTTPHeaderField:
                "Authorization"
        )

        // =====================================================
        // 时间
        // =====================================================

        let formatter =
            DateFormatter()

        formatter.dateFormat =
            "yyyy-MM-dd HH:mm:ss"

        formatter.locale =
            Locale(identifier: "en_US_POSIX")

        formatter.timeZone =
            TimeZone.current

        let capturedAt =
            formatter.string(
                from: Date()
            )

        // =====================================================
        // 测试数据
        // =====================================================

        let payload:
            [String: Any] = [

            "device_id":
                "iphone11-01",

            "event_id":
                UUID().uuidString,

            "captured_at":
                capturedAt,

            "source":
                "xianyu",

            "payload": [

                "test":
                    true,

                "message":
                    "hello from iPhone V0.2",

                "device":
                    "iPhone 11",

                "network_test":
                    true
            ]
        ]

        // =====================================================
        // JSON
        // =====================================================

        do {

            request.httpBody =
                try JSONSerialization.data(
                    withJSONObject:
                        payload,
                    options: []
                )

        } catch {

            updateStatus(
                "JSON生成失败：\(error.localizedDescription)"
            )

            return
        }

        // =====================================================
        // 上传
        // =====================================================

        let task =
            URLSession.shared.dataTask(
                with: request
            ) { data, response, error in

                if let error = error {

                    updateStatus(
                        "网络错误：\(error.localizedDescription)"
                    )

                    return
                }

                guard let httpResponse =
                    response
                    as? HTTPURLResponse
                else {

                    updateStatus(
                        "服务器响应异常"
                    )

                    return
                }

                let responseText: String

                if let data = data,
                   let text =
                    String(
                        data: data,
                        encoding: .utf8
                    ) {

                    responseText = text

                } else {

                    responseText = ""
                }

                if (200...299).contains(
                    httpResponse.statusCode
                ) {

                    updateStatus(
                        """
                        上传成功

                        HTTP \(httpResponse.statusCode)

                        \(responseText)
                        """
                    )

                } else {

                    updateStatus(
                        """
                        上传失败

                        HTTP \(httpResponse.statusCode)

                        \(responseText)
                        """
                    )
                }
            }

        task.resume()
    }

    private func updateStatus(
        _ text: String
    ) {
        DispatchQueue.main.async {
            status = text
        }
    }
}
