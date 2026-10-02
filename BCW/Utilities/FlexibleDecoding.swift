import Foundation

/// Le API di Classeviva non sono documentate ufficialmente e i tipi dei campi
/// cambiano di tanto in tanto (numeri come stringhe, booleani come 0/1, ecc.).
/// Questi helper rendono la decodifica tollerante: un campo inatteso non fa
/// fallire l'intera risposta.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

extension KeyedDecodingContainer where Key == AnyKey {
    func string(_ key: String) -> String? {
        let k = AnyKey(key)
        if let v = try? decodeIfPresent(String.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: k) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: k) { return String(v) }
        if let v = try? decodeIfPresent(Bool.self, forKey: k) { return String(v) }
        return nil
    }

    func int(_ key: String) -> Int? {
        let k = AnyKey(key)
        if let v = try? decodeIfPresent(Int.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: k) { return Int(v) }
        if let v = try? decodeIfPresent(String.self, forKey: k) { return Int(v) }
        return nil
    }

    func double(_ key: String) -> Double? {
        let k = AnyKey(key)
        if let v = try? decodeIfPresent(Double.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(String.self, forKey: k) {
            return Double(v.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func bool(_ key: String) -> Bool {
        let k = AnyKey(key)
        if let v = try? decodeIfPresent(Bool.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: k) { return v != 0 }
        if let v = try? decodeIfPresent(String.self, forKey: k) {
            return ["true", "1", "s", "si", "sì", "y", "yes"].contains(v.lowercased())
        }
        return false
    }

    func array<T: Decodable>(_ key: String, of type: T.Type = T.self) -> [T] {
        (try? decodeIfPresent(LossyArray<T>.self, forKey: AnyKey(key)))?.elements ?? []
    }

    func object<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        try? decodeIfPresent(T.self, forKey: AnyKey(key))
    }
}

/// Array che scarta gli elementi non decodificabili invece di fallire.
struct LossyArray<T: Decodable>: Decodable {
    var elements: [T]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [T] = []
        while !container.isAtEnd {
            if let value = try? container.decode(T.self) {
                result.append(value)
            } else {
                _ = try? container.decode(Discard.self)
            }
        }
        elements = result
    }

    /// Consuma un valore qualsiasi senza leggerlo, per far avanzare il cursore.
    private struct Discard: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

/// Identificatore deterministico (djb2) per gli elementi senza un id dal server.
enum StableID {
    static func make(_ parts: String...) -> Int {
        var hash: UInt64 = 5381
        for byte in parts.joined(separator: "|").utf8 {
            hash = (hash &<< 5) &+ hash &+ UInt64(byte)
        }
        return Int(truncatingIfNeeded: hash & 0x7FFF_FFFF_FFFF)
    }
}
