import Foundation

/// Transport boundary for the structured AI refinement step. The app target
/// implements this with the packaged provider-neutral coding client; tests
/// implement it with stubs. Only derived candidate features — never photo
/// bytes — cross this boundary.
public protocol EstimateRefinementTransport {
    func complete(_ prompt: String) async throws -> String
}

public enum EstimateRefinementError: Error, Equatable {
    case transportFailed
    case responseUnparseable
    case responseIncomplete
}

/// Parses the model's structured estimate response. Tolerates code fences and
/// surrounding prose, enforces value constraints, and maps item names back to
/// the known food database so a hallucinated entry can never reach the log.
public struct StructuredEstimateParser {
    public init() {}

    public func parse(_ raw: String, database: FoodDatabase) throws -> MealEstimate {
        guard let object = StructuredEstimateParser.extractJSONObject(from: raw),
              let data = object.data(using: .utf8) else {
            throw EstimateRefinementError.responseUnparseable
        }
        let decoded: RefinedEstimatePayload
        do {
            decoded = try JSONDecoder().decode(RefinedEstimatePayload.self, from: data)
        } catch {
            throw EstimateRefinementError.responseUnparseable
        }
        var items: [FoodItem] = []
        for entry in decoded.items.prefix(8) {
            let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let reference = database.reference(named: trimmedName) else { continue }
            let portion = min(max(entry.portionGrams, 1), 2000)
            let confidence = min(max(entry.confidence, 0), 1)
            items.append(FoodItem(
                name: reference.name,
                portionGrams: portion.rounded(toPlaces: 0),
                carbsGrams: reference.carbs(forPortionGrams: portion),
                confidence: confidence.rounded(toPlaces: 2)
            ))
        }
        guard !items.isEmpty else {
            throw EstimateRefinementError.responseIncomplete
        }
        let overall = min(max(decoded.overallConfidence, 0), 1)
        return MealEstimate(
            items: items,
            overallConfidence: overall.rounded(toPlaces: 2),
            analyzerVersion: RefiningMealAnalyzer.refinerVersion
        )
    }

    /// Extracts the first balanced top-level JSON object, skipping code fences
    /// and any prose the model adds around the payload. Normalizes the common
    /// model-output quirks: UTF-8 BOM, smart quotes, and trailing commas.
    static func extractJSONObject(from raw: String) -> String? {
        var text = raw
        if text.hasPrefix("\u{FEFF}") {
            text = String(text.dropFirst())
        }
        text = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
        text = StructuredEstimateParser.removingTrailingCommas(text)
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            }
            index = text.index(after: index)
        }
        guard let closing = end else { return nil }
        return String(text[start...closing])
    }

    /// Removes commas that appear immediately before a closing `}` or `]`
    /// outside of string literals — a frequent model-output quirk.
    static func removingTrailingCommas(_ text: String) -> String {
        var result = ""
        var inString = false
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }
            if character == "\"" {
                inString = true
                result.append(character)
                index = text.index(after: index)
                continue
            }
            if character == "," {
                var lookahead = text.index(after: index)
                while lookahead < text.endIndex, text[lookahead].isWhitespace {
                    lookahead = text.index(after: lookahead)
                }
                if lookahead < text.endIndex, text[lookahead] == "}" || text[lookahead] == "]" {
                    index = text.index(after: index)
                    continue
                }
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result
    }
}

private struct RefinedEstimatePayload: Decodable {
    struct Item: Decodable {
        let name: String
        let portionGrams: Double
        let carbsGrams: Double
        let confidence: Double

        enum CodingKeys: String, CodingKey {
            case name
            case portionGrams = "portion_grams"
            case carbsGrams = "carbs_grams"
            case confidence
        }
    }

    let items: [Item]
    let overallConfidence: Double

    enum CodingKeys: String, CodingKey {
        case items
        case overallConfidence = "overall_confidence"
    }
}

/// AI-first analyzer: the photo is preprocessed on device into a candidate
/// plate composition, then a structured refinement request tightens portions,
/// carb values and confidence. The output stays editable and is only saved
/// after explicit user confirmation, exactly like the on-device baseline.
public struct RefiningMealAnalyzer: MealAnalyzer {
    public static let refinerVersion = "structured-refine-v1.0"

    public let analyzerVersion = RefiningMealAnalyzer.refinerVersion

    private let transport: EstimateRefinementTransport
    private let database: FoodDatabase
    private let baseline: HeuristicMealAnalyzer
    private let parser: StructuredEstimateParser

    public init(transport: EstimateRefinementTransport, database: FoodDatabase = FoodDatabase()) {
        self.transport = transport
        self.database = database
        self.baseline = HeuristicMealAnalyzer(database: database)
        self.parser = StructuredEstimateParser()
    }

    public func analyze(photo: PhotoInput) async throws -> MealEstimate {
        // On-device preprocessing: derive candidate composition locally. Only
        // these derived features — never the photo — are sent for refinement.
        let candidates = (try? await baseline.analyze(photo: photo))?.items ?? []
        guard !candidates.isEmpty else {
            throw AnalysisError.imageUnreadable
        }
        let prompt = RefiningMealAnalyzer.buildPrompt(candidates: candidates, database: database)
        let raw: String
        do {
            raw = try await transport.complete(prompt)
        } catch {
            throw AnalysisError.serviceUnavailable
        }
        do {
            return try parser.parse(raw, database: database)
        } catch {
            throw AnalysisError.serviceUnavailable
        }
    }

    static func buildPrompt(candidates: [FoodItem], database: FoodDatabase) -> String {
        let candidatePayload: [[String: Any]] = candidates.map { item in
            [
                "name": item.name,
                "typical_serving_grams": database.reference(named: item.name)?.typicalServingGrams ?? item.portionGrams,
                "heuristic_portion_grams": item.portionGrams,
                "heuristic_confidence": item.confidence,
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: candidatePayload, options: [.sortedKeys])) ?? Data()
        let candidatesJSON = String(data: data, encoding: .utf8) ?? "[]"
        return """
        You refine a meal carb estimate for a glucose-conscious user. \
        You are given candidate foods detected on the user's plate with rough portions. \
        Correct portion sizes and carb values using typical restaurant portions, and recalibrate confidence.
        Respond with exactly one JSON object and no other text, code fences, or explanation:
        {"items":[{"name":"<food name from candidates>","portion_grams":<number 1-2000>,"carbs_grams":<number 0-500>,"confidence":<number 0-1>}],"overall_confidence":<number 0-1>}
        Rules: keep only candidate names; drop duplicates; 1-8 items; decimals allowed; \
        lower confidence when the photo-derived input is uncertain.
        Candidates: \(candidatesJSON)
        """
    }
}

/// Composes the AI refinement path with the deterministic on-device baseline.
/// Any refinement failure (offline, service unavailable, malformed response)
/// falls back to the on-device estimate so the capture flow always completes;
/// the manual log remains available throughout.
public struct FallbackMealAnalyzer: MealAnalyzer {
    public var analyzerVersion: String { "\(primary.analyzerVersion)+\(fallback.analyzerVersion)" }

    private let primary: MealAnalyzer
    private let fallback: MealAnalyzer

    public init(primary: MealAnalyzer, fallback: MealAnalyzer) {
        self.primary = primary
        self.fallback = fallback
    }

    public func analyze(photo: PhotoInput) async throws -> MealEstimate {
        do {
            return try await primary.analyze(photo: photo)
        } catch let error as AnalysisError {
            switch error {
            case .serviceUnavailable:
                return try await fallback.analyze(photo: photo)
            case .imageUnreadable, .lowConfidence:
                throw error
            }
        }
    }
}
