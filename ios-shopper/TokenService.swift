import Foundation

struct LiveKitTokenResponse: Decodable {
    let token: String
    let url: String
}

enum TokenServiceError: Error {
    case invalidResponse
}

struct TokenService {
    let endpoint = URL(string: "https://divisa-shopper-ios.onrender.com/token")!

    func token(room: String, identity: String, name: String) async throws -> LiveKitTokenResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "room": room,
            "identity": identity,
            "name": name
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw TokenServiceError.invalidResponse
        }
        return try JSONDecoder().decode(LiveKitTokenResponse.self, from: data)
    }
}
