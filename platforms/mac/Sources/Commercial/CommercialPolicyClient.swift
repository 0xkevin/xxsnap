import Foundation

struct CommercialPolicyFetchResponse: Equatable {
    let envelope: SignedEnvelope
    let serverVerifiedAt: Date?
}

protocol CommercialPolicyFetching {
    func fetchPolicy(locale: CommercialLocale) async throws -> SignedEnvelope
    func fetchPolicyResponse(locale: CommercialLocale) async throws -> CommercialPolicyFetchResponse
    func startTrial(_ request: CommercialTrialStartRequest, locale: CommercialLocale) async throws -> SignedEnvelope
    func activate(_ request: CommercialLicenseActivateRequest, locale: CommercialLocale) async throws -> SignedEnvelope
    func validate(_ request: CommercialLicenseValidateRequest, locale: CommercialLocale) async throws -> SignedEnvelope
    func deactivate(_ request: CommercialLicenseDeactivateRequest, locale: CommercialLocale) async throws
}

extension CommercialPolicyFetching {
    func fetchPolicyResponse(locale: CommercialLocale) async throws -> CommercialPolicyFetchResponse {
        CommercialPolicyFetchResponse(
            envelope: try await fetchPolicy(locale: locale),
            serverVerifiedAt: nil
        )
    }
}

enum CommercialPolicyClientError: Error, Equatable {
    case invalidOrigin
    case malformedResponse
    case unexpectedStatus(Int)
    case server(status: Int, error: CommercialAPIErrorDetail)
    case transport
}

final class CommercialPolicyClient: CommercialPolicyFetching {
    private static let host = "download.xxsofts.com"
    private static let timeout: TimeInterval = 15

    private let origin: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let redirectDelegate = CommercialSessionDelegate()

    init(origin: URL, session: URLSession) throws {
        guard Self.isAllowedProductionOrigin(origin) else {
            throw CommercialPolicyClientError.invalidOrigin
        }
        self.origin = origin
        self.session = session
    }

    convenience init(bundle: Bundle = .main, session: URLSession = .shared) throws {
        guard let value = bundle.object(forInfoDictionaryKey: "XXCommercialAPIOrigin") as? String,
              let origin = URL(string: value)
        else { throw CommercialPolicyClientError.invalidOrigin }
        try self.init(origin: origin, session: session)
    }

    func fetchPolicy(locale: CommercialLocale) async throws -> SignedEnvelope {
        try await fetchPolicyResponse(locale: locale).envelope
    }

    func fetchPolicyResponse(locale: CommercialLocale) async throws -> CommercialPolicyFetchResponse {
        let request = try makeRequest(
            path: "/api/v1/commercial/policy",
            method: "GET",
            body: nil,
            locale: locale
        )
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            try throwResponseError(status: response.statusCode, data: data)
        }
        let envelope: SignedEnvelope
        do {
            envelope = try decoder.decode(SignedEnvelope.self, from: data)
        } catch {
            throw CommercialPolicyClientError.malformedResponse
        }
        return CommercialPolicyFetchResponse(
            envelope: envelope,
            serverVerifiedAt: Self.strictHTTPDate(response.value(forHTTPHeaderField: "Date"))
        )
    }

    func startTrial(
        _ request: CommercialTrialStartRequest,
        locale: CommercialLocale
    ) async throws -> SignedEnvelope {
        try await envelope(path: "/api/v1/commercial/trials/start", body: request, locale: locale)
    }

    func activate(
        _ request: CommercialLicenseActivateRequest,
        locale: CommercialLocale
    ) async throws -> SignedEnvelope {
        try await envelope(path: "/api/v1/commercial/licenses/activate", body: request, locale: locale)
    }

    func validate(
        _ request: CommercialLicenseValidateRequest,
        locale: CommercialLocale
    ) async throws -> SignedEnvelope {
        try await envelope(path: "/api/v1/commercial/licenses/validate", body: request, locale: locale)
    }

    func deactivate(
        _ request: CommercialLicenseDeactivateRequest,
        locale: CommercialLocale
    ) async throws {
        let urlRequest = try makeRequest(
            path: "/api/v1/commercial/licenses/deactivate",
            method: "POST",
            body: encoder.encode(request),
            locale: locale
        )
        let (data, response) = try await perform(urlRequest)
        guard response.statusCode == 204, data.isEmpty else {
            try throwResponseError(status: response.statusCode, data: data)
        }
    }

    private func envelope<Body: Encodable>(
        path: String,
        method: String = "POST",
        body: Body?,
        locale: CommercialLocale
    ) async throws -> SignedEnvelope {
        let bodyData = try body.map(encoder.encode)
        let request = try makeRequest(path: path, method: method, body: bodyData, locale: locale)
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            try throwResponseError(status: response.statusCode, data: data)
        }
        do {
            return try decoder.decode(SignedEnvelope.self, from: data)
        } catch {
            throw CommercialPolicyClientError.malformedResponse
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        body: Data?,
        locale: CommercialLocale
    ) throws -> URLRequest {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            throw CommercialPolicyClientError.invalidOrigin
        }
        components.path = path
        guard let url = components.url else { throw CommercialPolicyClientError.invalidOrigin }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: Self.timeout
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(locale.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CommercialPolicyClientError.malformedResponse
            }
            return (data, httpResponse)
        } catch let error as CommercialPolicyClientError {
            throw error
        } catch {
            throw CommercialPolicyClientError.transport
        }
    }

    private func throwResponseError(status: Int, data: Data) throws -> Never {
        if let envelope = try? decoder.decode(CommercialAPIErrorEnvelope.self, from: data) {
            throw CommercialPolicyClientError.server(status: status, error: envelope.error)
        }
        throw CommercialPolicyClientError.unexpectedStatus(status)
    }

    static func isAllowedProductionOrigin(_ origin: URL) -> Bool {
        guard let components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme == "https"
            && components.host == host
            && components.user == nil
            && components.password == nil
            && (components.port == nil || components.port == 443)
            && (components.path.isEmpty || components.path == "/")
            && components.query == nil
            && components.fragment == nil
    }

    private static func strictHTTPDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            return nil
        }
        return date
    }
}

final class CommercialSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func redirectedRequest(_ request: URLRequest, statusCode: Int) -> URLRequest? {
        guard (300..<400).contains(statusCode),
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "download.xxsofts.com",
              components.user == nil,
              components.password == nil,
              (components.port == nil || components.port == 443)
        else { return nil }
        return request
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(redirectedRequest(request, statusCode: response.statusCode))
    }
}
