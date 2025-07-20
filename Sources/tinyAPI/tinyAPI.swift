import Foundation

// MARK: - Core Protocol
public protocol TinyAPIEndpoint: Sendable {
    var baseURL: String { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String]? { get }
    var queryItems: [URLQueryItem]? { get }
    var body: Data? { get }
}

// MARK: - HTTP Method
public enum HTTPMethod: String, Sendable {
    case GET, POST, PUT, DELETE, PATCH
}

// MARK: - API Errors
public enum TinyAPIError: Error, LocalizedError, Sendable {
    case invalidURL
    case noData
    case decodingError(String)
    case httpError(Int)
    case networkError(String)

    public var errorDescription: String? {
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
public enum RequestState<T: Sendable>: Sendable, Equatable where T: Equatable {
    case idle
    case loading
    case success(T)
    case failure(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var data: T? {
        if case .success(let data) = self { return data }
        return nil
    }

    public var error: String? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

// MARK: - Main API Client as Dependency
public struct TinyAPIClient: Sendable {
    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // Generic request method
    public func request<T: Codable & Sendable>(_ endpoint: TinyAPIEndpoint, as type: T.Type) async throws -> T {
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
    public func requestData(_ endpoint: TinyAPIEndpoint) async throws -> Data {
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
public struct SimpleEndpoint: TinyAPIEndpoint {
    public let baseURL: String
    public let path: String
    public let method: HTTPMethod
    public let headers: [String: String]?
    public let queryItems: [URLQueryItem]?
    public let body: Data?

    public init(
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
public extension TinyAPIClient {
    // GET request
    public func get<T: Codable & Sendable>(
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
    public func post<T: Codable & Sendable, U: Codable & Sendable>(
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
    public func put<T: Codable & Sendable, U: Codable & Sendable>(
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
    public func delete<T: Codable & Sendable>(
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
public struct MockTinyAPIClient: Sendable {
    private let decoder: JSONDecoder
    private let delay: TimeInterval

    public init(delay: TimeInterval = 0.5) {
        self.decoder = JSONDecoder()
        self.delay = delay
    }

    // Generic request method that loads from local JSON
    public func request<T: Codable & Sendable>(_ endpoint: TinyAPIEndpoint, as type: T.Type) async throws -> T {
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
    public func requestData(_ endpoint: TinyAPIEndpoint) async throws -> Data {
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
public extension MockTinyAPIClient {
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
    public func post<T: Codable & Sendable, U: Codable & Sendable>(
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
public protocol APIClientProtocol: Sendable {
    func request<T: Codable & Sendable>(_ endpoint: TinyAPIEndpoint, as type: T.Type) async throws -> T
    func requestData(_ endpoint: TinyAPIEndpoint) async throws -> Data
}

extension TinyAPIClient: APIClientProtocol {}
extension MockTinyAPIClient: APIClientProtocol {}

// MARK: - Dependency Registration for tinyTCA
public extension TinyAPIClient {
    static let live = TinyAPIClient()
}

public extension MockTinyAPIClient {
    static let preview = MockTinyAPIClient(delay: 0.1) // Fast for previews
    static let testing = MockTinyAPIClient(delay: 0.0) // Instant for tests
    static let demo = MockTinyAPIClient(delay: 1.0) // Realistic delay for demos
}
