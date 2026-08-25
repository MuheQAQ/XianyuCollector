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

            Text(status)
                .foregroundColor(.secondary)

            Button("测试上传") {
                uploadTestData()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func uploadTestData() {
        status = "正在上传..."

        guard let url = URL(
            string: "https://api.529059096.xyz/v1/metrics"
        ) else {
            status = "API地址错误"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        let payload: [String: Any] = [
            "device_id": "iphone11-01",
            "event_id": UUID().uuidString,
            "captured_at": formatter.string(from: Date()),
            "source": "xianyu",
            "payload": [
                "test": true,
                "message": "hello from iPhone"
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: payload,
                options: []
            )
        } catch {
            status = "JSON生成失败"
            return
        }

        URLSession.shared.dataTask(
            with: request
        ) { data, response, error in

            DispatchQueue.main.async {
                if let error = error {
                    status = "上传失败：\(error.localizedDescription)"
                    return
                }

                guard let httpResponse =
                    response as? HTTPURLResponse
                else {
                    status = "服务器响应异常"
                    return
                }

                if (200...299).contains(httpResponse.statusCode) {
                    status = "上传成功 HTTP \(httpResponse.statusCode)"
                } else {
                    status = "服务器错误 HTTP \(httpResponse.statusCode)"
                }
            }

        }.resume()
    }
}