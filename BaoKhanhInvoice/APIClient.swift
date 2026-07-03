import Foundation

final class APIClient {
    static func createInvoice(apiBase: String, token: String, request: CreateInvoiceRequest) async throws -> CreateInvoiceResponse {
        try await post(apiBase: apiBase, token: token, path: "/create_invoice.php", body: request)
    }

    static func checkStatus(apiBase: String, token: String, orderCode: String) async throws -> StatusResponse {
        let encoded = orderCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? orderCode
        return try await get(apiBase: apiBase, token: token, path: "/status.php?order_code=\(encoded)")
    }

    private static func normalizedBase(_ apiBase: String) -> String {
        let trimmed = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private static func makeRequest(apiBase: String, token: String, path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: normalizedBase(apiBase) + path) else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-BK-Token")
        }
        return request
    }

    private static func post<T: Decodable, B: Encodable>(apiBase: String, token: String, path: String, body: B) async throws -> T {
        var request = try makeRequest(apiBase: apiBase, token: token, path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return try decodeResponse(data: data, response: response)
    }

    private static func get<T: Decodable>(apiBase: String, token: String, path: String) async throws -> T {
        let request = try makeRequest(apiBase: apiBase, token: token, path: path, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        return try decodeResponse(data: data, response: response)
    }

    private static func decodeResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let message = extractMessage(data) {
                throw APIError.server(message)
            }
            throw APIError.server("API lỗi HTTP \(http.statusCode).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let message = extractMessage(data) {
                throw APIError.server(message)
            }
            throw APIError.invalidResponse
        }
    }

    private static func extractMessage(_ data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = obj["message"] as? String,
            !message.isEmpty
        else { return nil }
        return message
    }
}
