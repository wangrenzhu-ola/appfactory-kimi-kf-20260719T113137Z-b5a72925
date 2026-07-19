import CryptoKit
import Foundation

enum EncodedMaterial2adddd042cf6 {
    static let pieces: [[UInt8]] = [[13, 43, 219, 112, 220, 182, 194, 30, 29, 190, 206, 214, 21, 239, 230, 140, 237, 183, 29, 75, 16, 35, 170], [40, 9], [251, 84, 169, 78, 50, 209, 200]]
    static let layout: [Int] = [2, 1, 0]

    static func key() -> SymmetricKey {
        let ordered = zip(layout, pieces).sorted { $0.0 < $1.0 }
        var bytes = ordered.flatMap { $0.1 }
        for index in bytes.indices { bytes[index] = bytes[index] &- 141 }
        for index in bytes.indices { bytes[index] = (bytes[index] >> 5) | (bytes[index] << 3) }
        for index in bytes.indices { bytes[index] = bytes[index] ^ 10 }
        return SymmetricKey(data: Data(bytes))
    }
}
