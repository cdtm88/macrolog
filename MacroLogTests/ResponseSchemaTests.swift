import Testing
import Foundation
@testable import MacroLog

/// The structured-output schema must stay inside the documented subset:
/// basic types plus enum/const/anyOf/allOf/$ref. Type-union arrays like
/// `"type": ["string", "null"]` are not in that set and risk a 400 on every
/// estimate — nullability must be expressed with anyOf.
struct ResponseSchemaTests {

    @Test func schemaSerialisesToJSON() throws {
        let data = try JSONSerialization.data(withJSONObject: EstimationPrompt.responseSchema)
        let roundTripped = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(roundTripped?["type"] as? String == "object")
        let properties = roundTripped?["properties"] as? [String: Any]
        #expect(properties?.count == 6)
    }

    @Test func noPropertyUsesArrayValuedType() throws {
        let properties = try #require(EstimationPrompt.responseSchema["properties"] as? [String: Any])
        for (name, value) in properties {
            let property = try #require(value as? [String: Any], "property \(name) is not an object")
            #expect(!(property["type"] is [Any]), "property \(name) uses an array-valued \"type\"")
            // Nullable fields must use anyOf of single-type objects instead.
            if let anyOf = property["anyOf"] as? [[String: Any]] {
                for branch in anyOf {
                    #expect(branch["type"] is String, "anyOf branch in \(name) must have a single string type")
                }
            }
        }
    }
}
