import Foundation

enum WeatherSnapshot {
    static func parse(_ data: Data) throws -> [String: Any] {
        guard data.count < 1_048_576,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = (root["current_condition"] as? [[String: Any]])?.first,
              let temperature = current["temp_C"] as? String, Double(temperature)?.isFinite == true,
              let description = (current["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String else {
            throw IntegrationFailure("invalidResponse", "Weather provider returned malformed data.")
        }
        let today = (root["weather"] as? [[String: Any]])?.first
        return ["available": true, "known": true, "enabled": true, "temperatureC": temperature,
                "description": description, "feelsLikeC": current["FeelsLikeC"] as? String ?? "",
                "humidity": current["humidity"] as? String ?? "", "windKmh": current["windspeedKmph"] as? String ?? "",
                "lowC": today?["mintempC"] as? String ?? "", "highC": today?["maxtempC"] as? String ?? "",
                "provider": "wttr.in", "updatedAt": ISO8601DateFormatter().string(from: Date())]
    }
}
final class WeatherIntegration: PillIntegration {
    private var enabled = false
    private var task: URLSessionDataTask?
    private var requestGeneration = 0
    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        super.start(callback); every(1800) { [weak self] in self?.refresh() }
    }
    override func refresh() {
        guard enabled else { publish(["available": false, "known": false, "enabled": false, "provider": "wttr.in"]); return }
        guard task == nil else { return }
        requestGeneration += 1; let token = requestGeneration
        let deliver: (Result<[String: Any], Error>) -> Void = { [weak self] result in
            guard let self = self, self.running, self.enabled, self.requestGeneration == token else { return }
            self.task = nil
            switch result {
            case .success(let state): self.publish(state)
            case .failure(let error):
                self.publish(["available": false, "known": false, "enabled": true, "provider": "wttr.in",
                              "lastErrorCode": "networkFailure", "lastError": String(describing: error)])
            }
        }
        var request = URLRequest(url: URL(string: "https://wttr.in/?format=j1")!, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        task = URLSession.shared.dataTask(with: request) { data, response, error in
            let result = Result<[String: Any], Error> {
                if let error = error { throw error }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200, let data = data else {
                    throw IntegrationFailure("networkFailure", "Weather provider request failed.")
                }
                return try WeatherSnapshot.parse(data)
            }
            DispatchQueue.main.async { deliver(result) }
        }
        task?.resume()
    }
    override func invoke(_ action: String, _ argument: Any) {
        switch action {
        case "refresh": enabled = true; refresh() // The explicit fetch button is consent.
        case "enable":
            guard let value = argument as? Bool else { fail(action, "invalidInput", "Expected enabled boolean."); return }
            enabled = value; if !value { requestGeneration += 1; task?.cancel(); task = nil }; refresh()
        default: super.invoke(action, argument)
        }
    }
    override func stop() { requestGeneration += 1; task?.cancel(); task = nil; enabled = false; super.stop() }
}
