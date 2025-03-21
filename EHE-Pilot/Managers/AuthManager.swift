import SwiftUI
import AppAuth
import Foundation

class AuthManager: ObservableObject {
    
    // Configuration properties
    @Published var issuerURL: URL
    private var _redirectURI: URL
    private let defaultClientID = "nChhwTBZ4SZJEg0QJftkWDkulGqIkIAsMLqXagFo"
    private var _clientID: String
    private let defaultScopes = "openid"
    
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
        issuerURL = URL(string: "https://ehepilot.com/o")!
        _redirectURI = URL(string: "ehepilot://oauth/callback")!
        _clientID = defaultClientID
        
        // Try to restore from keychain if available
        loadAuthStateFromKeychain()
    }
    
    // MARK: - Property accessors
    
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
            self.issuerURL = newIssuerURL
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
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
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
                        
                        // Save auth state to keychain
                        self.saveAuthStateToKeychain()
                        
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
                        
                        // Fetch user profile after successful authentication
                        self.fetchUserProfile { _ in }
                    }
                }
            }
        }
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
            authState.performAction { [weak self] accessToken, idToken, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if let error = error {
                        print("Token refresh error: \(error.localizedDescription)")
                        self.statusMessage = "Token refresh failed"
                        completion(nil)
                        return
                    }
                    
                    self.statusMessage = "Token refreshed successfully"
                    
                    // Save the updated auth state
                    self.saveAuthStateToKeychain()
                    
                    completion(accessToken)
                }
            }
            return
        }
        
        // Manual refresh is not implemented - use AppAuth flow instead
        self.statusMessage = "Refresh not available, please sign in again"
        completion(nil)
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
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
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
                        
                        // Print the profile data for debugging
                        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                           let jsonStr = String(data: jsonData, encoding: .utf8) {
                            print("Profile Data:")
                            print(jsonStr)
                        }
                        
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
        
        return false
    }
    
    // MARK: - Session Management
    
    func signOut() {
        authState = nil
        tokenResponse = nil
        profileData = nil
        isAuthenticated = false
        statusMessage = "Signed out"
        
        // Clear keychain
        deleteAuthStateFromKeychain()
    }
    
    // MARK: - Keychain Storage
    
    private func saveAuthStateToKeychain() {
        guard let authState = authState else { return }
        
        do {
            let authStateData = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: false)
            
            // Save to keychain
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "AuthState",
                kSecValueData as String: authStateData
            ]
            
            // First delete any existing item
            SecItemDelete(query as CFDictionary)
            
            // Then add the new item
            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                print("Failed to save auth state to keychain: \(status)")
            }
        } catch {
            print("Failed to archive auth state: \(error)")
        }
    }
    
    private func loadAuthStateFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "AuthState",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            do {
                if let authState = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? OIDAuthState {
                    self.authState = authState
                    self.isAuthenticated = true
                    
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
                    
                    print("Restored auth state from keychain")
                    
                    // Verify the token is still valid
                    if authState.isAuthorized {
                        self.statusMessage = "Session restored"
                        self.fetchUserProfile { _ in }
                    } else {
                        self.refreshTokenIfNeeded { _ in }
                    }
                }
            } catch {
                print("Failed to unarchive auth state: \(error)")
            }
        }
    }
    
    private func deleteAuthStateFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "AuthState"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Failed to delete auth state from keychain: \(status)")
        }
    }
    
    // MARK: - Helper Methods
    
    func getPatientIdFromProfile() -> String {
        if let profileData = self.profileData,
           let patient = profileData["patient"] as? [String: Any],
           let id = patient["id"] as? Int {
            return "\(id)"
        }
        return "40010"  // Default to 40010 as requested
    }

    // MARK: - Simplified Flow (Direct Code Exchange)
        
    func swapCodeForToken(code: String, completion: @escaping (Bool) -> Void) {
        // 需要发现配置中的令牌端点
        if discoveryConfig == nil {
            discoverConfiguration { [weak self] success in
                guard let self = self, success else {
                    DispatchQueue.main.async {
                        self?.statusMessage = "Failed to discover configuration"
                        completion(false)
                    }
                    return
                }
                
                // 递归调用，现在已经有了配置
                self.swapCodeForToken(code: code, completion: completion)
            }
            return
        }
        
        guard let tokenEndpoint = discoveryConfig?["token_endpoint"] as? String,
              let tokenURL = URL(string: tokenEndpoint) else {
            statusMessage = "Missing token endpoint"
            completion(false)
            return
        }
        
        // 准备请求数据 - 使用固定的 PKCE 验证器
        let staticCodeVerifier = "f28984eaebcf41d881223399fc8eab27eaa374a9a8134eb3a900a3b7c0e6feab5b427479f3284ebe9c15b698849b0de2"
        
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
        
        // 转换参数为表单编码字符串
        let formString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = formString.data(using: .utf8)
        
        // 发送请求
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
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
                        
                        // 获取用户信息
                        self.fetchUserProfile { _ in }
                        
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
}
