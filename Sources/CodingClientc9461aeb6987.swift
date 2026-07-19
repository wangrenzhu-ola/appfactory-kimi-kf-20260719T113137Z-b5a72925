import CryptoKit
import Foundation

public struct CodingServiceClientb1a83a234d0c {
    public struct Completion: Encodable {
        public let requestIdentity: String
        public let content: String
        public let resultSHA256: String

        enum CodingKeys: String, CodingKey {
            case requestIdentity = "request_identity"
            case content
            case resultSHA256 = "result_sha256"
        }
    }

    public init() {}

    public func complete(_ prompt: String) async throws -> String {
        try await completeWithEvidence(prompt).content
    }

    public func completeWithEvidence(_ prompt: String) async throws -> Completion {
        let nonce = try AES.GCM.Nonce(data: Data([29, 160, 192, 74, 70, 84, 81, 41, 73, 235, 108, 191]))
        let box = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: Data([23, 1, 174, 98, 153, 119, 251, 208, 101, 151, 164, 102, 93, 188, 185, 116, 41, 57, 83, 105, 29, 231, 196, 201, 166, 219, 43, 111, 94, 144, 241, 131, 59, 195, 184, 249, 106, 237, 111, 74, 153, 129, 199, 227, 194, 143, 249, 201, 59, 100, 206, 164, 249, 72, 34, 136, 158, 35, 164, 146, 207, 182, 175, 4, 211, 37, 129, 118, 205, 138, 125]),
            tag: Data([10, 67, 152, 153, 18, 235, 244, 15, 75, 50, 208, 142, 132, 187, 113, 84]))
        let clear = try AES.GCM.open(box, using: EncodedMaterial2adddd042cf6.key())
        let configuration = try JSONDecoder().decode(Configuration.self, from: clear)
        guard let base = URL(string: configuration.baseURL),
              let url = URL(string: "chat/completions", relativeTo: base) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        let requestIdentity = UUID().uuidString.lowercased()
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(requestIdentity, forHTTPHeaderField: "X-Request-ID")
        request.setValue("Bearer \(try CredentialEnvelope55505113c2a8.reveal())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: configuration.model,
            messages: [Message(role: "user", content: prompt)]))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let content = try JSONDecoder().decode(ResponseBody.self, from: data).choices[0].message.content
        let resultSHA256 = SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return Completion(
            requestIdentity: requestIdentity,
            content: content,
            resultSHA256: resultSHA256)
    }

    private struct Configuration: Decodable { let baseURL: String; let model: String }
    private struct Message: Codable { let role: String; let content: String }
    private struct RequestBody: Encodable { let model: String; let messages: [Message] }
    private struct ResponseBody: Decodable { let choices: [Choice] }
    private struct ResponseMessage: Decodable { let content: String }
    private struct Choice: Decodable { let message: ResponseMessage }
}
