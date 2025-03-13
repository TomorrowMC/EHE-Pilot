import SwiftUI
import AppAuth
import Foundation

class AuthManager: ObservableObject {
    
    // Configuration properties
    private var _issuerURL: URL
    private var _redirectURI: URL
    private let defaultClientID = "nChhwTBZ4SZJEg0QJftkWDkulGqIkIAsMLqXagFo"
    private var _clientID: String
    private let defaultScopes = "openid"
    
    // Static code verifier (matching the Python code)
    private let staticCodeVerifier = "f28984eaebcf41d881223399fc8eab27eaa374a9a8134eb3a900a3b7c0e6feab5b427479f3284ebe9c15b698849b0de2"
    
    // AppAuth session
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    
    // Published properties for UI updates
    @Published var authState: OIDAuthState?
    @Published var isAuthenticated: Bool = false
    @Published var discoveryConfig: [String: Any]?
    @Published var tokenResponse: [String: Any]?
    @Published var profileData: [String: Any]?
    @Published var statusMessage: String = "Not authenticated"
    
    // MARK: - Initialization
    
    init() {
        _issuerURL = URL(string: "https://ehepilot.com/o")!
        _redirectURI = URL(string: "ehepilot://oauth/callback")!
        _clientID = defaultClientID
    }
    
    // MARK: - Property accessors
    
    var issuerURL: URL {
        return _issuerURL
    }
    
    var redirectURI: URL {
        return _redirectURI
    }
    
    var clientID: String {
        return _clientID
    }
    
    // MARK: - Configuration Management
    
    /// Updates the OAuth configuration with custom values
    /// - Parameters:
    ///   - issuerURL: The custom issuer URL
    ///   - redirectURI: The custom redirect URI
    ///   - clientID: Optional custom client ID
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func updateConfiguration(issuerURL: URL? = nil, redirectURI: URL? = nil, clientID: String? = nil) -> Bool {
        var configChanged = false
        
        if let newIssuerURL = issuerURL {
            _issuerURL = newIssuerURL
            configChanged = true
        }
        
        if let newRedirectURI = redirectURI {
            _redirectURI = newRedirectURI
            configChanged = true
        }
        
        if let newClientID = clientID {
            _clientID = newClientID
            configChanged = true
        }
        
        // Reset all authentication state when configuration changes
        if configChanged {
            discoveryConfig = nil
            tokenResponse = nil
            authState = nil
            isAuthenticated = false
            statusMessage = "Configuration updated"
        }
        
        return configChanged
    }
    
    // MARK: - Configuration Discovery
    
    func discoverConfiguration(completion: @escaping (Bool) -> Void) {
        let discoveryEndpoint = issuerURL.appendingPathComponent("/.well-known/openid-configuration")
        
        var request = URLRequest(url: discoveryEndpoint)
        request.httpMethod = "GET"
        
        // Use the insecure session for development
        let task = URLSession.insecureSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Error discovering OIDC configuration: \(error.localizedDescription)")
                    self.statusMessage = "Failed to discover OIDC configuration"
                    completion(false)
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("Invalid response from discovery endpoint")
                    self.statusMessage = "Invalid response from discovery endpoint"
                    completion(false)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.discoveryConfig = json
                        print("Successfully discovered OIDC configuration")
                        self.statusMessage = "OIDC configuration discovered"
                        completion(true)
                    } else {
                        print("Could not parse OIDC configuration")
                        self.statusMessage = "Could not parse OIDC configuration"
                        completion(false)
                    }
                } catch {
                    print("Error parsing OIDC configuration: \(error.localizedDescription)")
                    self.statusMessage = "Error parsing OIDC configuration"
                    completion(false)
                }
            }
        }
        
        task.resume()
    }
    
    // MARK: - Standard OAuth Flow
    
    func signIn() {
        // Use AppAuth for standard flow with dynamic code verifier
        OIDAuthorizationService.discoverConfiguration(forIssuer: issuerURL) { [weak self] configuration, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error discovering configuration: \(error.localizedDescription)")
                self.statusMessage = "Discovery error: \(error.localizedDescription)"
                return
            }
            
            guard let config = configuration else {
                print("Missing configuration")
                self.statusMessage = "Missing configuration"
                return
            }
            
            // Generate PKCE challenge
            let codeVerifier = OIDAuthorizationRequest.generateCodeVerifier()
            let codeChallenge = OIDAuthorizationRequest.codeChallengeS256(forVerifier: codeVerifier)
            
            let request = OIDAuthorizationRequest(
                configuration: config,
                clientId: self.clientID,
                clientSecret: nil,
                scope: self.defaultScopes,
                redirectURL: self.redirectURI,
                responseType: OIDResponseTypeCode,
                state: nil,
                nonce: nil,
                codeVerifier: codeVerifier,
                codeChallenge: codeChallenge,
                codeChallengeMethod: OIDOAuthorizationRequestCodeChallengeMethodS256,
                additionalParameters: nil
            )
            
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController else {
                print("No root view controller found")
                self.statusMessage = "No root view controller found"
                return
            }
            
            self.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: rootViewController) { authState, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Authorization error: \(error.localizedDescription)")
                        self.statusMessage = "Authorization failed: \(error.localizedDescription)"
                        return
                    }
                    
                    if let authState = authState {
                        self.authState = authState
                        self.isAuthenticated = true
                        self.statusMessage = "Authentication successful"
                        
                        // Extract token response data
                        if let tokenResponse = authState.lastTokenResponse {
                            var tokenData: [String: Any] = [:]
                            if let accessToken = tokenResponse.accessToken {
                                tokenData["access_token"] = accessToken
                            }
                            if let refreshToken = tokenResponse.refreshToken {
                                tokenData["refresh_token"] = refreshToken
                            }
                            if let idToken = tokenResponse.idToken {
                                tokenData["id_token"] = idToken
                            }
                            self.tokenResponse = tokenData
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Simplified Flow (Direct Code Exchange)
    
    func swapCodeForToken(code: String, completion: @escaping (Bool) -> Void) {
        guard let tokenEndpoint = discoveryConfig?["token_endpoint"] as? String,
              let tokenURL = URL(string: tokenEndpoint) else {
            statusMessage = "Missing token endpoint"
            completion(false)
            return
        }
        
        // Prepare request data
        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI.absoluteString,
            "client_id": clientID,
            "code_verifier": staticCodeVerifier
        ]
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Convert parameters to form url encoded string
        let formString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = formString.data(using: .utf8)
        
        // Use the insecure session for development
        let task = URLSession.insecureSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Token exchange error: \(error.localizedDescription)")
                    self.statusMessage = "Token exchange failed"
                    completion(false)
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("Invalid token response")
                    self.statusMessage = "Invalid token response"
                    completion(false)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.tokenResponse = json
                        self.isAuthenticated = true
                        self.statusMessage = "Token exchange successful"
                        completion(true)
                    } else {
                        print("Could not parse token response")
                        self.statusMessage = "Could not parse token response"
                        completion(false)
                    }
                } catch {
                    print("Error parsing token response: \(error.localizedDescription)")
                    self.statusMessage = "Error parsing token response"
                    completion(false)
                }
            }
        }
        
        task.resume()
    }
    
    // MARK: - Token Management
    
    func currentAccessToken() -> String? {
        // First check AppAuth state
        if let token = authState?.lastTokenResponse?.accessToken {
            return token
        }
        
        // Then check manual token response
        return tokenResponse?["access_token"] as? String
    }
    
    func refreshTokenIfNeeded(completion: @escaping (String?) -> Void) {
        // If using AppAuth, use its refresh mechanism
        if let authState = authState {
            authState.setNeedsTokenRefresh()
            authState.performAction { accessToken, idToken, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Token refresh error: \(error.localizedDescription)")
                        self.statusMessage = "Token refresh failed"
                        completion(nil)
                        return
                    }
                    
                    self.statusMessage = "Token refreshed successfully"
                    completion(accessToken)
                }
            }
            return
        }
        
        // Manual refresh using direct API call
        guard let refreshToken = tokenResponse?["refresh_token"] as? String,
              let tokenEndpoint = discoveryConfig?["token_endpoint"] as? String else {
            statusMessage = "No refresh token available"
            completion(nil)
            return
        }
        
        let parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let formString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = formString.data(using: .utf8)
        
        let task = URLSession.insecureSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Token refresh error: \(error.localizedDescription)")
                    self.statusMessage = "Token refresh failed"
                    completion(nil)
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("Invalid refresh response")
                    self.statusMessage = "Invalid refresh response"
                    completion(nil)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.tokenResponse = json
                        self.statusMessage = "Token refreshed successfully"
                        completion(json["access_token"] as? String)
                    } else {
                        print("Could not parse refresh response")
                        self.statusMessage = "Could not parse refresh response"
                        completion(nil)
                    }
                } catch {
                    print("Error parsing refresh response: \(error.localizedDescription)")
                    self.statusMessage = "Error parsing refresh response"
                    completion(nil)
                }
            }
        }
        
        task.resume()
    }
    
    // MARK: - API Test
    
    func fetchUserProfile(completion: @escaping (Bool) -> Void) {
        guard let accessToken = currentAccessToken() else {
            statusMessage = "No access token available"
            completion(false)
            return
        }
        
        // Use the base URL from the issuer URL to construct the profile endpoint
        let baseURLString = issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        let profileURL = URL(string: "\(baseURLString)/api/v1/users/profile")!
        
        var request = URLRequest(url: profileURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.insecureSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Profile fetch error: \(error.localizedDescription)")
                    self.statusMessage = "Profile fetch failed"
                    completion(false)
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("Invalid profile response")
                    self.statusMessage = "Invalid profile response"
                    completion(false)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.profileData = json
                        self.statusMessage = "Profile fetched successfully"
                        completion(true)
                    } else {
                        print("Could not parse profile response")
                        self.statusMessage = "Could not parse profile response"
                        completion(false)
                    }
                } catch {
                    print("Error parsing profile response: \(error.localizedDescription)")
                    self.statusMessage = "Error parsing profile response"
                    completion(false)
                }
            }
        }
        
        task.resume()
    }
    
    // MARK: - URL Callback Handling
    
    func handleRedirectURL(_ url: URL) -> Bool {
        if let authorizationFlow = currentAuthorizationFlow, authorizationFlow.resumeExternalUserAgentFlow(with: url) {
            currentAuthorizationFlow = nil
            return true
        }
        
        // Parse the URL for the authorization code if using manual flow
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let codeItem = queryItems.first(where: { $0.name == "code" }),
           let code = codeItem.value {
            
            swapCodeForToken(code: code) { success in
                print("Manual code exchange: \(success ? "successful" : "failed")")
            }
            return true
        }
        
        return false
    }
    
    // MARK: - Session Management
    
    func signOut() {
        authState = nil
        tokenResponse = nil
        profileData = nil
        isAuthenticated = false
        statusMessage = "Signed out"
    }
}

// Extension for URL Session with insecure SSL handling (only for development/testing)
extension URLSession {
    // For development/testing only
    static var insecureSession: URLSession {
        let configuration = URLSessionConfiguration.default
        let delegate = InsecureURLSessionDelegate()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

// WARNING: Use only in development/test environments
class InsecureURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        // Accept any SSL certificate (UNSAFE for production!)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
