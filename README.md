# PersistenceCore

A lightweight Swift Package providing type-safe, generic local persistence primitives for iOS apps following Clean Architecture. Drop it into any SPM-based project and stop rewriting `UserDefaults` and Keychain boilerplate across every feature module.

```swift
// Store any Codable type in two lines
let store = UserDefaultsStore<User>(key: "com.app.user")
try await store.save(user)

// Sensitive data goes to the Keychain
let keychain = KeychainStore(service: "com.app.auth")
try keychain.save(token, forKey: "authToken")
```

---

## Why PersistenceCore?

Most iOS projects end up with the same `UserDefaults` wrapper written three or four times across different feature modules, and Keychain code copy-pasted from Stack Overflow. `PersistenceCore` solves this once:

- **Generic** — works with any `Codable` type including arrays, enums, and nested structs
- **Zero dependencies** — pure Swift, only Foundation and Security framework
- **Testable by design** — inject a custom `UserDefaults` suite in tests, no global state pollution
- **Clean Architecture ready** — sits at the infrastructure layer, invisible above your Data layer
- **Tiny** — two files, two types, does exactly one thing

---

## Requirements

| | Minimum |
|---|---|
| iOS | 17.0 |
| Swift | 5.9 |
| Xcode | 15.0 |

---

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** and enter the repository URL:

```
https://github.com/your-username/PersistenceCore
```

Or add it directly to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Koronaa/PersistenceCore", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "PersistenceCore", package: "PersistenceCore")
        ]
    )
]
```

---

## Usage

### UserDefaultsStore

Store any `Codable` value — structs, arrays, enums — behind a string key.

```swift
import PersistenceCore

struct UserProfile: Codable {
    let id: String
    let name: String
    let email: String
}

let store = UserDefaultsStore<UserProfile>(key: "com.app.userProfile")

// Save
let profile = UserProfile(id: "123", name: "Kenji", email: "kenji@example.com")
try await store.save(profile)

// Fetch — returns nil if nothing stored yet
if let saved = try await store.fetch() {
    print(saved.name) // "Kenji"
}

// Clear
await store.clear()
```

**Arrays work identically:**

```swift
let store = UserDefaultsStore<[String]>(key: "com.app.recentSearches")
try await store.save(["Tokyo", "Osaka", "Kyoto"])
let searches = try await store.fetch() ?? []
```

**Custom UserDefaults suite (e.g. App Groups for widget sharing):**

```swift
let sharedDefaults = UserDefaults(suiteName: "group.com.yourapp.shared")!
let store = UserDefaultsStore<UserProfile>(
    key: "com.app.userProfile",
    defaults: sharedDefaults
)
```

---

### KeychainStore

Store sensitive string values — auth tokens, API keys, passwords — securely in the iOS Keychain. **Never store tokens in `UserDefaults`** — it is not encrypted.

```swift
import PersistenceCore

let keychain = KeychainStore(service: "com.yourapp.auth")

// Save
try keychain.save("eyJhbGciOiJIUzI1NiJ9...", forKey: "authToken")

// Fetch — returns nil if key not found
if let token = try keychain.fetch(forKey: "authToken") {
    // use token
}

// Clear on logout
try keychain.clear(forKey: "authToken")
```

---

## Error Handling

Both stores throw on failure. Wrap calls in `do/catch` or propagate with `throws`:

```swift
do {
    try await store.save(profile)
} catch {
    // UserDefaults: JSONEncoder failure (malformed Codable conformance)
    // Keychain: KeychainStore.KeychainError.saveFailed(OSStatus)
    print("Persistence error: \(error)")
}
```

`KeychainStore` throws typed errors you can match on:

```swift
catch KeychainStore.KeychainError.saveFailed(let status) {
    print("Keychain save failed with OSStatus: \(status)")
}
```

---

## Clean Architecture Integration

`PersistenceCore` is designed to sit at the **infrastructure layer** alongside a networking module. It has zero knowledge of your domain models — feature Data targets wire it to domain-specific repository implementations.

### Recommended structure

```
YourApp/
  Packages/
    ├── PersistenceCore       ← this package
    ├── NetworkCore           ← your networking module
    ├── CoreDomain            ← shared models + repository protocols
    ├── AuthData              ← depends on PersistenceCore + NetworkCore
    └── RideData              ← depends on PersistenceCore + NetworkCore
```

### Example: repository implementation

Define the protocol in your Domain layer — it has no dependency on `PersistenceCore`:

```swift
// CoreDomain/Repositories/UserRepository.swift

public protocol UserRepository {
    func saveUser(_ user: User) throws
    func fetchUser() throws -> User?
    func clearUser() throws
}
```

Implement it in your Data layer using `PersistenceCore`:

```swift
// AuthData/Repositories/UserRepositoryImpl.swift

import CoreDomain
import PersistenceCore

public final class UserRepositoryImpl: UserRepository {
    private let store = UserDefaultsStore<User>(key: "com.app.user")

    public init() {}

    public func saveUser(_ user: User) throws { try store.save(user) }
    public func fetchUser() throws -> User?   { try store.fetch() }
    public func clearUser() throws            { store.clear() }
}
```

The rest of your app — use cases, ViewModels, Views — only ever see `UserRepository`. `PersistenceCore` is an implementation detail invisible above the Data layer.

---

## Testing

### Option 1 — Mock the protocol (recommended)

In most cases you don't need to test `PersistenceCore` at all. Mock the repository protocol with an in-memory implementation — no `UserDefaults`, no Keychain, no disk I/O:

```swift
final class MockUserRepository: UserRepository {
    private var stored: User?

    func saveUser(_ user: User) throws { stored = user }
    func fetchUser() throws -> User?  { stored }
    func clearUser() throws           { stored = nil }
}

// In your test
let viewModel = ProfileViewModel(userRepository: MockUserRepository())
```

### Option 2 — Test the store directly

When you do want to test a real `UserDefaultsStore`, inject a UUID-named suite to avoid polluting `.standard` and guarantee a clean slate per test run:

```swift
final class UserDefaultsStoreTests: XCTestCase {
    var sut: UserDefaultsStore<UserProfile>!
    var suiteName: String!

    override func setUp() {
        suiteName = "com.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        sut = UserDefaultsStore<UserProfile>(key: "test.profile", defaults: defaults)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        sut = nil
    }

    func test_save_andFetch_roundtrip() async throws {
        let profile = UserProfile(id: "1", name: "Kenji", email: "k@example.com")
        try await sut.save(profile)
        let fetched = try await sut.fetch()
        XCTAssertEqual(fetched?.id, profile.id)
        XCTAssertEqual(fetched?.name, profile.name)
    }

    func test_fetch_returnsNil_whenNothingStored() async throws {
        XCTAssertNil(try await sut.fetch())
    }

    func test_clear_removesStoredValue() async throws {
        try await sut.save(UserProfile(id: "1", name: "Kenji", email: "k@example.com"))
        await sut.clear()
        XCTAssertNil(try await sut.fetch())
    }
}
```

---

## Storage Key Conventions

Use reverse-DNS namespacing to prevent key collisions across features and teams:

```swift
// Good — unambiguous, feature-scoped
"com.yourapp.auth.user"
"com.yourapp.ride.recentRides"
"com.yourapp.onboardingStatus"

// Avoid — too generic, easy to collide
"user"
"token"
"data"
```

Define keys as private constants inside each repository implementation — never scatter raw strings across files.

---

## Module Structure

```
PersistenceCore/
  ├── Package.swift
  ├── README.md
  ├── LICENSE
  └── Sources/
       └── PersistenceCore/
            ├── UserDefaultsStore.swift
            └── KeychainStore.swift
```

---

## Contributing

Contributions are welcome. Please open an issue before submitting a pull request for anything beyond bug fixes so the scope and approach can be discussed first.

When contributing:

- Keep `PersistenceCore` zero-dependency — PRs that add third-party dependencies will not be merged
- New storage backends (CoreData, SQLite) should be separate packages following the same pattern, not additions here
- All public API must include documentation comments
- Include tests for any new functionality

---

## License

MIT. See [LICENSE](LICENSE) for details.
