<picture>
  <source srcset="SVG/tinyAPI-dark.svg" media="(prefers-color-scheme: dark)">
  <img src="SVG/tinyAPI-light.svg" alt="tinyAPI logo">
</picture>

A minimal, Swift 6 concurrency-compliant networking framework designed specifically for [tinyTCA](https://github.com/roberthein/tinyTCA) applications. tinyAPI provides a lightweight, type-safe approach to API communication with built-in support for async/await, local JSON mocking, and seamless TCA integration.

## Requirements

- **Swift 6.0+** with strict concurrency enabled
- **SwiftUI** framework
- **iOS 15.0+** / **macOS 12.0+** / **tvOS 15.0+** / **watchOS 8.0+**
- **tinyTCA** for state management integration

> ⚠️ **Important**: This framework requires Swift 6 strict concurrency mode and is designed to work seamlessly with tinyTCA's Feature pattern.

## Features

- 🎯 **TCA-First Design**: Built specifically for tinyTCA's Feature pattern
- ⚡ **Swift 6 Ready**: Full compliance with Swift 6 strict concurrency
- 🔄 **Async/Await**: Modern networking with async/await throughout
- 🛡️ **Type Safety**: End-to-end type safety with Codable support
- 🧪 **Mock Support**: Local JSON file loading for testing and previews
- 📱 **RequestState**: Built-in state management for API call lifecycle
- 🎛️ **Dependency Injection**: Easy switching between live and mock implementations

## Core Concepts

### API Client

The heart of tinyAPI is the `TinyAPIClient` that handles all network communication:

```swift
let apiClient = TinyAPIClient()

// Simple GET request
let users = try await apiClient.get(
    from: "https://api.example.com",
    path: "/users",
    as: [User].self
)

// POST with body
let newUser = try await apiClient.post(
    to: "https://api.example.com",
    path: "/users",
    body: CreateUserRequest(name: "John", email: "john@example.com"),
    as: User.self
)
```

### Endpoint Protocol

Define your API endpoints using the `TinyAPIEndpoint` protocol:

```swift
enum UserEndpoint {
    case list
    case create(CreateUserRequest)
    case detail(id: Int)
    case update(id: Int, user: User)
    case delete(id: Int)
}

extension UserEndpoint: TinyAPIEndpoint {
    var baseURL: String { "https://api.example.com" }
    
    var path: String {
        switch self {
        case .list: return "/users"
        case .create: return "/users"
        case .detail(let id): return "/users/\(id)"
        case .update(let id, _): return "/users/\(id)"
        case .delete(let id): return "/users/\(id)"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .list, .detail: return .GET
        case .create: return .POST
        case .update: return .PUT
        case .delete: return .DELETE
        }
    }
    
    var body: Data? {
        switch self {
        case .create(let request):
            return try? JSONEncoder().encode(request)
        case .update(_, let user):
            return try? JSONEncoder().encode(user)
        default:
            return nil
        }
    }
    
    var headers: [String: String]? { nil }
    var queryItems: [URLQueryItem]? { nil }
}
```

### RequestState Integration

tinyAPI includes `RequestState<T>` that perfectly integrates with tinyTCA's state management:

```swift
struct UserListFeature: Feature {
    struct State: Sendable, Equatable {
        var users: RequestState<[User]> = .idle
        var selectedUser: User?
    }
    
    enum Action: Sendable {
        case loadUsers
        case usersResponse(Result<[User], TinyAPIError>)
        case selectUser(User)
    }
    
    static var initialState: State { State() }
    
    static func reducer(state: inout State, action: Action) throws {
        switch action {
        case .loadUsers:
            state.users = .loading
            
        case .usersResponse(.success(let users)):
            state.users = .success(users)
            
        case .usersResponse(.failure(let error)):
            state.users = .failure(error.localizedDescription)
            
        case .selectUser(let user):
            state.selectedUser = user
        }
    }
    
    static func effect(for action: Action, state: State) async throws -> Action? {
        let apiClient = APIClientDependency.live.client
        
        switch action {
        case .loadUsers:
            do {
                let users = try await apiClient.request(UserEndpoint.list, as: [User].self)
                return .usersResponse(.success(users))
            } catch let error as TinyAPIError {
                return .usersResponse(.failure(error))
            } catch {
                return .usersResponse(.failure(.networkError(error.localizedDescription)))
            }
            
        default:
            return nil
        }
    }
}
```

### SwiftUI Integration

Use RequestState directly in your SwiftUI views:

```swift
struct UserListView: View {
    @StoreState private var state: UserListFeature.State
    
    init(store: Store<UserListFeature>) {
        self._state = StoreState(store)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                switch state.users {
                case .idle:
                    Text("Tap to load users")
                    
                case .loading:
                    ProgressView("Loading users...")
                    
                case .success(let users):
                    List(users, id: \.id) { user in
                        VStack(alignment: .leading) {
                            Text(user.name).font(.headline)
                            Text(user.email).font(.caption).foregroundColor(.secondary)
                        }
                        .onTapGesture {
                            $state.send(.selectUser(user))
                        }
                    }
                    
                case .failure(let error):
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Users")
            .toolbar {
                Button("Load") {
                    $state.send(.loadUsers)
                }
            }
        }
    }
}
```

## Mock System

### Local JSON Files

tinyAPI includes a powerful mock system that loads local JSON files automatically:

```swift
// Mock client maps endpoints to JSON files:
// GET /users → mock_get_users.json
// POST /users → mock_post_users.json
// GET /users/1 → mock_get_users_1.json

let mockClient = MockTinyAPIClient()
let users = try await mockClient.request(UserEndpoint.list, as: [User].self)
```

### JSON File Examples

Create these files in your app bundle:

**mock_get_users.json**
```json
[
  {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com"
  },
  {
    "id": 2,
    "name": "Jane Smith",
    "email": "jane@example.com"
  }
]
```

**mock_post_users.json**
```json
{
  "id": 999,
  "name": "New User",
  "email": "new@example.com"
}
```

### Dependency Injection

Switch between live and mock implementations easily:

```swift
struct APIClientDependency {
    let client: any APIClientProtocol
    
    static let live = APIClientDependency(client: TinyAPIClient.live)
    static let mock = APIClientDependency(client: MockTinyAPIClient.demo)
    static let preview = APIClientDependency(client: MockTinyAPIClient.preview)
    static let testing = APIClientDependency(client: MockTinyAPIClient.testing)
}
```

## Installation

### Swift Package Manager

Add tinyAPI to your project using Xcode:

1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/yourusername/tinyAPI`
3. Choose your version requirements

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/tinyAPI", from: "1.0.0"),
    .package(url: "https://github.com/roberthein/tinyTCA", from: "1.0.0")
]
```

## Usage Patterns

### Simple API Feature

```swift
struct PostsFeature: Feature {
    struct State: Sendable, Equatable {
        var posts: RequestState<[Post]> = .idle
    }
    
    enum Action: Sendable {
        case loadPosts
        case postsResponse(Result<[Post], TinyAPIError>)
    }
    
    static var initialState: State { State() }
    
    static func reducer(state: inout State, action: Action) throws {
        switch action {
        case .loadPosts:
            state.posts = .loading
        case .postsResponse(.success(let posts)):
            state.posts = .success(posts)
        case .postsResponse(.failure(let error)):
            state.posts = .failure(error.localizedDescription)
        }
    }
    
    static func effect(for action: Action, state: State) async throws -> Action? {
        switch action {
        case .loadPosts:
            do {
                let posts = try await APIClientDependency.live.client.get(
                    from: "https://jsonplaceholder.typicode.com",
                    path: "/posts",
                    as: [Post].self
                )
                return .postsResponse(.success(posts))
            } catch let error as TinyAPIError {
                return .postsResponse(.failure(error))
            }
        default:
            return nil
        }
    }
}
```

### SwiftUI Previews

Use different mock configurations for previews:

```swift
#Preview("Loading") {
    UserListView(store: .preview(UserListFeature.State(users: .loading)))
}

#Preview("Success") {
    let users = [
        User(id: 1, name: "Preview User", email: "preview@example.com")
    ]
    UserListView(store: .preview(UserListFeature.State(users: .success(users))))
}

#Preview("Error") {
    UserListView(store: .preview(UserListFeature.State(users: .failure("Network error"))))
}
```

## Architecture Guidelines

### Endpoint Design
- Use enums to represent all API endpoints for a feature
- Include request data as associated values
- Keep endpoint logic focused and simple

### State Management
- Use `RequestState<T>` for all API call states
- Handle loading, success, and error states explicitly
- Keep state mutations in the reducer only

### Effect Guidelines
- Perform all API calls in the effect function
- Always return an action with the result
- Handle both success and error cases
- Use dependency injection for testability

### Error Handling
- Use `TinyAPIError` for structured error information
- Provide meaningful error messages to users
- Log detailed errors for debugging

## Performance Considerations

- All network calls are async and don't block the main thread
- JSON decoding happens off the main thread
- State updates are batched efficiently
- Mock system has configurable delays for realistic testing

## Swift 6 Concurrency Compliance

tinyAPI is built from the ground up for Swift 6 strict concurrency:

- All types conform to `Sendable` where required
- No data races between network calls and state updates
- Proper actor isolation for UI updates
- Full async/await support throughout

## Testing

### Unit Testing with Mocks

```swift
func testUserLoading() async throws {
    let feature = UserListFeature.self
    let mockClient = MockTinyAPIClient.testing
    
    // Test loading state
    var state = feature.initialState
    try feature.reducer(state: &state, action: .loadUsers)
    XCTAssertEqual(state.users, .loading)
    
    // Test success response
    let users = [User(id: 1, name: "Test", email: "test@example.com")]
    try feature.reducer(state: &state, action: .usersResponse(.success(users)))
    XCTAssertEqual(state.users, .success(users))
}
```

### Integration Testing

```swift
func testRealAPIIntegration() async throws {
    let client = TinyAPIClient.live
    let users = try await client.get(
        from: "https://jsonplaceholder.typicode.com",
        path: "/users",
        as: [User].self
    )
    XCTAssertFalse(users.isEmpty)
}
```

## Contributing

Contributions are welcome! Please ensure all code:

- Maintains Swift 6 strict concurrency compliance
- Includes appropriate tests for both live and mock implementations
- Follows tinyTCA architectural patterns
- Includes proper error handling

## Acknowledgments

This framework is designed to complement [tinyTCA](https://github.com/roberthein/tinyTCA) and follows similar architectural principles. Special thanks to the tinyTCA project for inspiration on minimal, type-safe architecture patterns.


## Full Disclosure
This entire framework, including its name, tagline, implementation, documentation, README, examples, and even this very disclaimer, was entirely generated by artificial intelligence. This is a demonstration of AI-assisted software development and should be thoroughly reviewed, tested, and validated before any production use.
## License

tinyAPI is available under the MIT license. See LICENSE file for more info.