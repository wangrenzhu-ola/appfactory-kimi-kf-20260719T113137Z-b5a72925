import Foundation

/// One entry in the bundled food knowledge base. Values are carbs per 100 g
/// and a typical serving size used for portion estimation.
public struct FoodReference: Equatable, Codable {
    public var name: String
    public var carbsPer100g: Double
    public var typicalServingGrams: Double
    public var keywords: [String]

    public init(name: String, carbsPer100g: Double, typicalServingGrams: Double, keywords: [String]) {
        self.name = name
        self.carbsPer100g = carbsPer100g
        self.typicalServingGrams = typicalServingGrams
        self.keywords = keywords
    }

    public func carbs(forPortionGrams grams: Double) -> Double {
        (carbsPer100g * grams / 100).rounded(toPlaces: 1)
    }
}

/// Local food knowledge base powering manual search and the heuristic
/// analyzer fallback. Ships with the app; works fully offline.
public struct FoodDatabase {
    public let references: [FoodReference]

    public init(references: [FoodReference] = FoodDatabase.bundled) {
        self.references = references
    }

    /// Case-insensitive substring search across names and keywords.
    public func search(_ query: String) -> [FoodReference] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return references.filter { ref in
            ref.name.lowercased().contains(trimmed)
                || ref.keywords.contains { $0.lowercased().contains(trimmed) }
        }
    }

    public func reference(named name: String) -> FoodReference? {
        references.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static let bundled: [FoodReference] = [
        FoodReference(name: "White rice, cooked", carbsPer100g: 28.2, typicalServingGrams: 158, keywords: ["rice", "grain", "bowl"]),
        FoodReference(name: "Brown rice, cooked", carbsPer100g: 23.0, typicalServingGrams: 195, keywords: ["rice", "grain", "whole grain"]),
        FoodReference(name: "Quinoa, cooked", carbsPer100g: 21.3, typicalServingGrams: 185, keywords: ["grain", "seed", "protein"]),
        FoodReference(name: "Spaghetti, cooked", carbsPer100g: 30.9, typicalServingGrams: 140, keywords: ["pasta", "noodle", "italian"]),
        FoodReference(name: "Whole wheat bread", carbsPer100g: 41.3, typicalServingGrams: 32, keywords: ["bread", "toast", "sandwich", "slice"]),
        FoodReference(name: "White bread", carbsPer100g: 49.4, typicalServingGrams: 30, keywords: ["bread", "toast", "sandwich", "slice"]),
        FoodReference(name: "Bagel", carbsPer100g: 53.0, typicalServingGrams: 105, keywords: ["bread", "breakfast", "bakery"]),
        FoodReference(name: "Oatmeal, cooked", carbsPer100g: 12.0, typicalServingGrams: 234, keywords: ["oats", "breakfast", "porridge"]),
        FoodReference(name: "Corn tortilla", carbsPer100g: 44.6, typicalServingGrams: 26, keywords: ["taco", "wrap", "mexican"]),
        FoodReference(name: "Flour tortilla", carbsPer100g: 49.0, typicalServingGrams: 49, keywords: ["taco", "wrap", "burrito", "mexican"]),
        FoodReference(name: "Baked potato", carbsPer100g: 21.2, typicalServingGrams: 173, keywords: ["potato", "side", "starch"]),
        FoodReference(name: "French fries", carbsPer100g: 41.0, typicalServingGrams: 117, keywords: ["potato", "fried", "fast food", "side"]),
        FoodReference(name: "Sweet potato, baked", carbsPer100g: 20.7, typicalServingGrams: 130, keywords: ["potato", "side", "starch"]),
        FoodReference(name: "Grilled chicken breast", carbsPer100g: 0.0, typicalServingGrams: 120, keywords: ["chicken", "protein", "meat"]),
        FoodReference(name: "Salmon, baked", carbsPer100g: 0.0, typicalServingGrams: 125, keywords: ["fish", "protein", "seafood"]),
        FoodReference(name: "Ground beef, cooked", carbsPer100g: 0.0, typicalServingGrams: 85, keywords: ["beef", "protein", "meat", "burger"]),
        FoodReference(name: "Scrambled eggs", carbsPer100g: 2.0, typicalServingGrams: 100, keywords: ["egg", "breakfast", "protein"]),
        FoodReference(name: "Black beans, cooked", carbsPer100g: 23.7, typicalServingGrams: 172, keywords: ["beans", "legume", "mexican", "protein"]),
        FoodReference(name: "Chickpeas, cooked", carbsPer100g: 27.4, typicalServingGrams: 164, keywords: ["beans", "legume", "hummus"]),
        FoodReference(name: "Caesar salad with dressing", carbsPer100g: 6.5, typicalServingGrams: 190, keywords: ["salad", "lettuce", "greens"]),
        FoodReference(name: "Garden salad", carbsPer100g: 4.0, typicalServingGrams: 150, keywords: ["salad", "lettuce", "greens", "vegetable"]),
        FoodReference(name: "Broccoli, steamed", carbsPer100g: 7.2, typicalServingGrams: 156, keywords: ["vegetable", "greens", "side"]),
        FoodReference(name: "Apple", carbsPer100g: 13.8, typicalServingGrams: 182, keywords: ["fruit", "snack"]),
        FoodReference(name: "Banana", carbsPer100g: 22.8, typicalServingGrams: 118, keywords: ["fruit", "snack", "breakfast"]),
        FoodReference(name: "Orange", carbsPer100g: 11.8, typicalServingGrams: 131, keywords: ["fruit", "citrus", "snack"]),
        FoodReference(name: "Grapes", carbsPer100g: 18.1, typicalServingGrams: 92, keywords: ["fruit", "snack"]),
        FoodReference(name: "Greek yogurt, plain", carbsPer100g: 3.6, typicalServingGrams: 170, keywords: ["yogurt", "dairy", "breakfast", "snack"]),
        FoodReference(name: "Milk, 2%", carbsPer100g: 4.8, typicalServingGrams: 244, keywords: ["dairy", "drink"]),
        FoodReference(name: "Cheddar cheese", carbsPer100g: 1.3, typicalServingGrams: 28, keywords: ["cheese", "dairy", "snack"]),
        FoodReference(name: "Pizza, cheese slice", carbsPer100g: 33.0, typicalServingGrams: 107, keywords: ["pizza", "italian", "fast food"]),
        FoodReference(name: "Cheeseburger", carbsPer100g: 24.0, typicalServingGrams: 150, keywords: ["burger", "fast food", "beef"]),
        FoodReference(name: "Sushi roll, California", carbsPer100g: 28.0, typicalServingGrams: 165, keywords: ["sushi", "rice", "japanese", "seafood"]),
        FoodReference(name: "Pad Thai", carbsPer100g: 24.0, typicalServingGrams: 300, keywords: ["noodle", "thai", "asian"]),
        FoodReference(name: "Burrito bowl", carbsPer100g: 18.0, typicalServingGrams: 350, keywords: ["mexican", "rice", "bowl", "beans"]),
        FoodReference(name: "Pancakes", carbsPer100g: 42.0, typicalServingGrams: 77, keywords: ["breakfast", "syrup", "bakery"]),
        FoodReference(name: "Granola bar", carbsPer100g: 64.0, typicalServingGrams: 28, keywords: ["snack", "oats", "bar"]),
        FoodReference(name: "Chocolate chip cookie", carbsPer100g: 64.0, typicalServingGrams: 16, keywords: ["dessert", "snack", "bakery", "sweet"]),
        FoodReference(name: "Vanilla ice cream", carbsPer100g: 23.6, typicalServingGrams: 66, keywords: ["dessert", "sweet", "dairy"]),
        FoodReference(name: "Cola, regular", carbsPer100g: 10.6, typicalServingGrams: 355, keywords: ["soda", "drink", "sweet"]),
        FoodReference(name: "Orange juice", carbsPer100g: 10.4, typicalServingGrams: 248, keywords: ["juice", "drink", "breakfast", "fruit"]),
        FoodReference(name: "Almonds", carbsPer100g: 21.6, typicalServingGrams: 28, keywords: ["nuts", "snack"]),
    ]
}

extension Double {
    /// Rounds to the given number of decimal places.
    public func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
