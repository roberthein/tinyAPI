import Foundation

// MARK: - Core Protocol
protocol TinyAPIEndpoint: Sendable {
    var baseURL: String { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String]? { get }
    var queryItems: [URLQueryItem]? { get }
    var body: Data? { get }
}

// MARK: - HTTP Method
enum HTTPMethod: String, Sendable {
    case GET, POST, PUT, DELETE, PATCH
}

// MARK: - API Errors
enum TinyAPIError: Error, LocalizedError, Sendable {
    case invalidURL
    case noData
    case decodingError(String)
    case httpError(Int)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .decodingError(let message): return "Decoding failed: \(message)"
        case .httpError(let code): return "HTTP Error: \(code)"
        case .networkError(let message): return "Network Error: \(message)"
        }
    }
}

// MARK: - Request State for TCA
enum RequestState<T: Sendable>: Sendable, Equatable where T: Equatable {
    case idle
    case loading
    case success(T)
    case failure(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var data: T? {
        if case .success(let data) = self { return data }
        return nil
    }

    var error: String? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

// MARK: - Main API Client as Dependency
struct TinyAPIClient: Sendable {
    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // Generic request method
    func request<T: Codable & Sendable>(_ endpoint: TinyAPIEndpoint, as type: T.Type) async throws -> T {
        let request = try buildRequest(from: endpoint)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TinyAPIError.networkError("Invalid response type")
            }

            guard 200...299 ~= httpResponse.statusCode else {
                throw TinyAPIError.httpError(httpResponse.statusCode)
            }

            guard !data.isEmpty else {
                throw TinyAPIError.noData
            }

            do {
                return try decoder.decode(type, from: data)
            } catch {
                throw TinyAPIError.decodingError(error.localizedDescription)
            }
        } catch let error as TinyAPIError {
            throw error
        } catch {
            throw TinyAPIError.networkError(error.localizedDescription)
        }
    }

    // Raw data request
    func requestData(_ endpoint: TinyAPIEndpoint) async throws -> Data {
        let request = try buildRequest(from: endpoint)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TinyAPIError.networkError("Invalid response type")
            }

            guard 200...299 ~= httpResponse.statusCode else {
                throw TinyAPIError.httpError(httpResponse.statusCode)
            }

            return data
        } catch let error as TinyAPIError {
            throw error
        } catch {
            throw TinyAPIError.networkError(error.localizedDescription)
        }
    }

    // Build URLRequest from endpoint
    private func buildRequest(from endpoint: TinyAPIEndpoint) throws -> URLRequest {
        guard var components = URLComponents(string: endpoint.baseURL) else {
            throw TinyAPIError.invalidURL
        }

        components.path = endpoint.path
        components.queryItems = endpoint.queryItems

        guard let url = components.url else {
            throw TinyAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body

        // Default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Custom headers
        endpoint.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}

// MARK: - Simple Endpoint Builder
struct SimpleEndpoint: TinyAPIEndpoint {
    let baseURL: String
    let path: String
    let method: HTTPMethod
    let headers: [String: String]?
    let queryItems: [URLQueryItem]?
    let body: Data?

    init(
        baseURL: String,
        path: String,
        method: HTTPMethod = .GET,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil
    ) {
        self.baseURL = baseURL
        self.path = path
        self.method = method
        self.headers = headers
        self.queryItems = queryItems
        self.body = body
    }
}

// MARK: - Convenience Extensions for Direct Usage
extension TinyAPIClient {
    // GET request
    func get<T: Codable & Sendable>(
        from baseURL: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil,
        as type: T.Type
    ) async throws -> T {
        let endpoint = SimpleEndpoint(
            baseURL: baseURL,
            path: path,
            method: .GET,
            headers: headers,
            queryItems: queryItems
        )
        return try await request(endpoint, as: type)
    }

    // POST request with Codable body
    func post<T: Codable & Sendable, U: Codable & Sendable>(
        to baseURL: String,
        path: String,
        body: T,
        headers: [String: String]? = nil,
        as type: U.Type
    ) async throws -> U {
        let bodyData = try encoder.encode(body)
        let endpoint = SimpleEndpoint(
            baseURL: baseURL,
            path: path,
            method: .POST,
            headers: headers,
            body: bodyData
        )
        return try await request(endpoint, as: type)
    }

    // PUT request with Codable body
    func put<T: Codable & Sendable, U: Codable & Sendable>(
        to baseURL: String,
        path: String,
        body: T,
        headers: [String: String]? = nil,
        as type: U.Type
    ) async throws -> U {
        let bodyData = try encoder.encode(body)
        let endpoint = SimpleEndpoint(
            baseURL: baseURL,
            path: path,
            method: .PUT,
            headers: headers,
            body: bodyData
        )
        return try await request(endpoint, as: type)
    }

    // DELETE request
    func delete<T: Codable & Sendable>(
        from baseURL: String,
        path: String,
        headers: [String: String]? = nil,
        as type: T.Type
    ) async throws -> T {
        let endpoint = SimpleEndpoint(
            baseURL: baseURL,
            path: path,
            method: .DELETE,
            headers: headers
        )
        return try await request(endpoint, as: type)
    }
}

// MARK: - Mock API Client for Local JSON
struct MockTinyAPIClient: Sendable {
    private let decoder: JSONDecoder
    private let delay: TimeInterval

    init(delay: TimeInterval = 0.5) {
        self.decoder = JSONDecoder()
        self.delay = delay
    }

    // Generic request method that loads from local JSON
    func request<T: Codable & Sendable>(_ endpoint: TinyAPIEndpoint, as type: T.Type) async throws -> T {
        // Simulate network delay
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        let fileName = mockFileName(for: endpoint)

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            throw TinyAPIError.invalidURL
        }

        let data = try Data(contentsOf: url)

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw TinyAPIError.decodingError(error.localizedDescription)
        }
    }

    // Raw data request for local files
    func requestData(_ endpoint: TinyAPIEndpoint) async throws -> Data {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        let fileName = mockFileName(for: endpoint)

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            throw TinyAPIError.invalidURL
        }

        return try Data(contentsOf: url)
    }

    // Generate filename based on endpoint
    private func mockFileName(for endpoint: TinyAPIEndpoint) -> String {
        let pathComponents = endpoint.path.components(separatedBy: "/").filter { !$0.isEmpty }
        let method = endpoint.method.rawValue.lowercased()

        if pathComponents.isEmpty {
            return "mock_\(method)_root"
        }

        // Create filename like: mock_get_users, mock_post_users, etc.
        let resourceName = pathComponents.joined(separator: "_")
        return "mock_\(method)_\(resourceName)"
    }
}

// MARK: - Convenience extensions for MockTinyAPIClient
extension MockTinyAPIClient {
    // GET request
    func get<T: Codable & Sendable>(
        from baseURL: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil,
        as type: T.Type
    ) async throws -> T {
        let endpoint = SimpleEndpoint(
            baseURL: baseURL,
            path: path,
            method: .GET,
            headers: headers,
            queryItems: queryItems
        )
        return try await request(endpoint, as: type)
    }

    // POST request with Codable body
    func post<T: Codable & Sendable, U: Codable & Sendable>(
        to baseURL: String,
        path: String,
        body: T,
        headers: [String: String]? = nil,
        as type: U.Type
    ) async throws -> U {
        let endpoint = SimpleEndpoint(
            baseURL: baseURL,
            path: path,
            method: .POST,
            headers: headers,
            body: nil // Mock ignores body, loads from file
        )
        return try await request(endpoint, as: type)
    }
}

// MARK: - Protocol for API Client abstraction
protocol APIClientProtocol: Sendable {
    func request<T: Codable & Sendable>(_ endpoint: TinyAPIEndpoint, as type: T.Type) async throws -> T
    func requestData(_ endpoint: TinyAPIEndpoint) async throws -> Data
}

extension TinyAPIClient: APIClientProtocol {}
extension MockTinyAPIClient: APIClientProtocol {}

// MARK: - Dependency Registration for tinyTCA
extension TinyAPIClient {
    static let live = TinyAPIClient()
}

extension MockTinyAPIClient {
    static let preview = MockTinyAPIClient(delay: 0.1) // Fast for previews
    static let testing = MockTinyAPIClient(delay: 0.0) // Instant for tests
    static let demo = MockTinyAPIClient(delay: 1.0) // Realistic delay for demos
}

// MARK: - Usage Example with tinyTCA
/*
 // MARK: - Models
 struct User: Codable, Sendable, Equatable {
 let id: Int
 let name: String
 let email: String
 }

 struct CreateUserRequest: Codable, Sendable {
 let name: String
 let email: String
 }

 // MARK: - API Endpoints
 enum UserEndpoint {
 case list
 case create(CreateUserRequest)
 case detail(id: Int)
 case update(id: Int, user: User)
 case delete(id: Int)
 }

 extension UserEndpoint: TinyAPIEndpoint {
 var baseURL: String { "https://jsonplaceholder.typicode.com" }

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

 var headers: [String: String]? { nil }
 var queryItems: [URLQueryItem]? { nil }

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
 }

 // MARK: - API Client Dependency for tinyTCA Features
 struct APIClientDependency {
 let client: any APIClientProtocol

 static let live = APIClientDependency(client: TinyAPIClient.live)
 static let mock = APIClientDependency(client: MockTinyAPIClient.demo)
 static let preview = APIClientDependency(client: MockTinyAPIClient.preview)
 static let testing = APIClientDependency(client: MockTinyAPIClient.testing)
 }

 // MARK: - tinyTCA Feature Implementation
 struct UserListFeature: Feature {
 struct State: Sendable, Equatable {
 var users: RequestState<[User]> = .idle
 var createUser: RequestState<User> = .idle
 var selectedUser: User?
 }

 enum Action: Sendable {
 case loadUsers
 case usersResponse(Result<[User], TinyAPIError>)
 case createUser(name: String, email: String)
 case createUserResponse(Result<User, TinyAPIError>)
 case selectUser(User)
 case deleteUser(id: Int)
 case deleteUserResponse(Result<Void, TinyAPIError>)
 }

 static var initialState: State {
 State()
 }

 static func reducer(state: inout State, action: Action) throws {
 switch action {
 case .loadUsers:
 state.users = .loading

 case .usersResponse(.success(let users)):
 state.users = .success(users)

 case .usersResponse(.failure(let error)):
 state.users = .failure(error.localizedDescription)

 case .createUser:
 state.createUser = .loading

 case .createUserResponse(.success(let user)):
 state.createUser = .success(user)
 // Add to existing users if they're loaded
 if case .success(var users) = state.users {
 users.append(user)
 state.users = .success(users)
 }

 case .createUserResponse(.failure(let error)):
 state.createUser = .failure(error.localizedDescription)

 case .selectUser(let user):
 state.selectedUser = user

 case .deleteUser:
 // Handle in effect
 break

 case .deleteUserResponse(.success):
 // Remove from users list if loaded
 if case .success(var users) = state.users {
 users.removeAll { $0.id == state.selectedUser?.id }
 state.users = .success(users)
 }
 state.selectedUser = nil

 case .deleteUserResponse(.failure(let error)):
 state.users = .failure(error.localizedDescription)
 }
 }

 static func effect(for action: Action, state: State) async throws -> Action? {
 // Use dependency injection - can be switched for testing/previews
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

 case .createUser(let name, let email):
 do {
 let request = CreateUserRequest(name: name, email: email)
 let user = try await apiClient.request(UserEndpoint.create(request), as: User.self)
 return .createUserResponse(.success(user))
 } catch let error as TinyAPIError {
 return .createUserResponse(.failure(error))
 } catch {
 return .createUserResponse(.failure(.networkError(error.localizedDescription)))
 }

 case .deleteUser(let id):
 do {
 _ = try await apiClient.requestData(UserEndpoint.delete(id: id))
 return .deleteUserResponse(.success(()))
 } catch let error as TinyAPIError {
 return .deleteUserResponse(.failure(error))
 } catch {
 return .deleteUserResponse(.failure(.networkError(error.localizedDescription)))
 }

 default:
 return nil
 }
 }
 }

 // MARK: - JSON File Examples
 /*
  Create these JSON files in your app bundle:

  // mock_get_users.json
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
  },
  {
  "id": 3,
  "name": "Bob Johnson",
  "email": "bob@example.com"
  }
  ]

  // mock_post_users.json
  {
  "id": 999,
  "name": "New User",
  "email": "new@example.com"
  }

  // mock_get_users_1.json (for user detail endpoint /users/1)
  {
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com"
  }
  */

 // MARK: - SwiftUI View
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
 Text(user.name)
 .font(.headline)
 Text(user.email)
 .font(.caption)
 .foregroundColor(.secondary)
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
 ToolbarItem(placement: .primaryAction) {
 Button("Load") {
 $state.send(.loadUsers)
 }
 }
 ToolbarItem(placement: .secondaryAction) {
 Button("Add User") {
 $state.send(.createUser(name: "New User", email: "new@example.com"))
 }
 .disabled(state.createUser.isLoading)
 }
 }
 }
 }
 }

 #Preview {
 // Use mock data for previews
 let mockFeature = UserListFeature.self
 // Override the dependency for preview
 UserListView(store: Store<UserListFeature>())
 }

 #Preview("With Data") {
 // Preview with pre-loaded state
 let previewState = UserListFeature.State(
 users: .success([
 User(id: 1, name: "Preview User 1", email: "preview1@example.com"),
 User(id: 2, name: "Preview User 2", email: "preview2@example.com")
 ])
 )
 UserListView(store: .preview(previewState))
 }

 #Preview("Loading State") {
 let loadingState = UserListFeature.State(users: .loading)
 UserListView(store: .preview(loadingState))
 }

 #Preview("Error State") {
 let errorState = UserListFeature.State(users: .failure("Network connection failed"))
 UserListView(store: .preview(errorState))
 }
 */
