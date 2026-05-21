//
//  UserDefaultsStore.swift
//  PersistenceCore
//
//  Created by Sajith Konara on 6/4/26.
//

import Foundation

public actor UserDefaultsStore<T: Codable> {

    private let key: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func save(_ value: T) throws {
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }

    public func fetch() throws -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try decoder.decode(T.self, from: data)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
