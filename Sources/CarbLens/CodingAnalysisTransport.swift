import Foundation

/// Bridges the core refinement boundary to the packaged provider-neutral
/// coding client. The credential never appears here: the generated client
/// reconstructs it in memory at call time.
struct CodingAnalysisTransport: EstimateRefinementTransport {
    private let client = CodingServiceClientb1a83a234d0c()

    func complete(_ prompt: String) async throws -> String {
        try await client.complete(prompt)
    }
}
