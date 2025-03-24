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
    
    // 在AuthManager类内部添加这些KeyChain相关的键名
    private let accessTokenKey = "com.EHE-Pilot.accessToken"
    private let refreshTokenKey = "com.EHE-Pilot.refreshToken"
    private let tokenExpiryKey = "com.EHE-Pilot.tokenExpiry"
    
    // MARK: - Initialization
    
    init() {
        issuerURL = URL(string: "https://ehepilot.com/o")!
        _redirectURI = URL(string: "ehepilot://oauth/callback")!
        _clientID = defaultClientID
        
        // Try to restore from keychain if available
        loadAuthStateFromKeychain()
    }
    // 在init()方法之后添加KeyChain存储方法
    private func saveTokenToKeychain(token: String, forKey key: String) {
        // 创建查询字典
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: token.data(using: .utf8)!
        ]
        
        // 先删除可能存在的旧值
        SecItemDelete(query as CFDictionary)
        
        // 然后添加新值
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to save token to keychain: \(status)")
        }
    }

    private func loadTokenFromKeychain(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data, let token = String(data: data, encoding: .utf8) {
            return token
        }
        
        return nil
    }

    private func deleteTokenFromKeychain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Failed to delete token from keychain: \(status)")
        }
    }

    // 保存Token过期时间到UserDefaults (不太敏感的信息可以放UserDefaults)
    private func saveTokenExpiry(date: Date?) {
        if let date = date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: tokenExpiryKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
        }
    }

    private func getTokenExpiry() -> Date? {
        if let timestamp = UserDefaults.standard.object(forKey: tokenExpiryKey) as? TimeInterval {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }

    // 添加保存和加载完整Token信息的方法
    func saveTokens(accessToken: String, refreshToken: String, expiresIn: TimeInterval = 1209600) { // 默认2周过期
        // 保存token到KeyChain
        saveTokenToKeychain(token: accessToken, forKey: accessTokenKey)
        saveTokenToKeychain(token: refreshToken, forKey: refreshTokenKey)
        
        // 计算并保存过期时间
        let expiryDate = Date().addingTimeInterval(expiresIn)
        saveTokenExpiry(date: expiryDate)
        
        // 更新状态
        self.tokenResponse = [
            "access_token": accessToken,
            "refresh_token": refreshToken
        ]
        self.isAuthenticated = true
    }

    // 从KeyChain加载Token
    func loadTokensFromStorage() -> Bool {
        guard let accessToken = loadTokenFromKeychain(forKey: accessTokenKey),
              let refreshToken = loadTokenFromKeychain(forKey: refreshTokenKey) else {
            return false
        }
        
        // 恢复token状态
        self.tokenResponse = [
            "access_token": accessToken,
            "refresh_token": refreshToken
        ]
        
        // 检查是否过期
        if let expiryDate = getTokenExpiry(), expiryDate > Date() {
            self.isAuthenticated = true
            return true
        } else {
            // Token可能已过期，需要刷新
            return false
        }
    }

    // 清除所有Token
    func clearStoredTokens() {
        deleteTokenFromKeychain(forKey: accessTokenKey)
        deleteTokenFromKeychain(forKey: refreshTokenKey)
        saveTokenExpiry(date: nil)
        self.tokenResponse = nil
        self.isAuthenticated = false
    }

    // 修改signOut方法以清除存储的Token
    func signOut() {
        authState = nil
        tokenResponse = nil
        profileData = nil
        isAuthenticated = false
        statusMessage = "Signed out"
        
        // 清除KeyChain中的auth状态和Token
        deleteAuthStateFromKeychain()
        clearStoredTokens()
    }

    // 添加自动登录方法
    func attemptAutoLogin(completion: @escaping (Bool) -> Void) {
        // 先尝试从KeyChain加载Token
        if loadTokensFromStorage() {
            // 成功加载Token，验证有效性
            verifyTokenValidity { [weak self] isValid in
                guard let self = self else { return }
                
                if isValid {
                    // Token有效，获取用户资料
                    self.fetchUserProfile { success in
                        self.isAuthenticated = success
                        completion(success)
                    }
                } else {
                    // Token无效，尝试刷新
                    self.refreshTokenWithStoredRefreshToken { refreshSuccess in
                        if refreshSuccess {
                            // 刷新成功，获取用户资料
                            self.fetchUserProfile { success in
                                self.isAuthenticated = success
                                completion(success)
                            }
                        } else {
                            // 刷新失败，需要重新登录
                            self.isAuthenticated = false
                            completion(false)
                        }
                    }
                }
            }
        } else {
            // KeyChain中没有Token
            completion(false)
        }
    }

    // 使用存储的refreshToken刷新accessToken
    func refreshTokenWithStoredRefreshToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = loadTokenFromKeychain(forKey: refreshTokenKey),
              let tokenEndpoint = discoveryConfig?["token_endpoint"] as? String,
              let tokenURL = URL(string: tokenEndpoint) else {
            completion(false)
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
        
        // 转换参数为表单编码字符串
        let formString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = formString.data(using: .utf8)
        
        // 发送请求
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Token refresh error: \(error.localizedDescription)")
                    self.statusMessage = "Token refresh failed"
                    completion(false)
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("Invalid token refresh response")
                    self.statusMessage = "Invalid token refresh response"
                    completion(false)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let accessToken = json["access_token"] as? String {
                        // 保存新的token
                        let refreshToken = json["refresh_token"] as? String ?? refreshToken
                        let expiresIn = json["expires_in"] as? TimeInterval ?? 1209600 // 默认2周
                        
                        self.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
                        self.statusMessage = "Token refreshed successfully"
                        completion(true)
                    } else {
                        print("Could not parse token refresh response")
                        self.statusMessage = "Could not parse token refresh response"
                        completion(false)
                    }
                } catch {
                    print("Error parsing token refresh response: \(error.localizedDescription)")
                    self.statusMessage = "Error parsing token refresh response"
                    completion(false)
                }
            }
        }
        
        task.resume()
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
    func verifyTokenValidity(completion: @escaping (Bool) -> Void) {
        guard let accessToken = currentAccessToken() else {
            isAuthenticated = false
            completion(false)
            return
        }
        
        // 选择一个轻量级API端点来验证令牌有效性
        let baseURLString = issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        guard let url = URL(string: "\(baseURLString)/api/v1/users/profile") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Token validation error: \(error.localizedDescription)")
                    // 令牌可能仍然有效，但网络问题导致请求失败
                    // 不要立即判断为无效，以避免不必要的登出
                    completion(true)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(false)
                    return
                }
                
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    // 令牌无效或过期
                    print("Token invalid - status code: \(httpResponse.statusCode)")
                    self.isAuthenticated = false
                    completion(false)
                } else if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // 令牌有效
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // 更新配置文件数据
                        self.profileData = json
                    }
                    completion(true)
                } else {
                    // 其他错误，保持当前状态
                    print("Unexpected status code during token validation: \(httpResponse.statusCode)")
                    completion(true)
                }
            }
        }
        
        task.resume()
    }
    /// 处理应用从后台恢复
    func handleAppResume() {
        // 如果已认证，验证令牌是否仍然有效
        if isAuthenticated {
            verifyTokenValidity { [weak self] isValid in
                guard let self = self else { return }
                
                if !isValid {
                    // 令牌无效，尝试刷新
                    self.refreshTokenIfNeeded { token in
                        if token == nil {
                            // 无法刷新令牌，需要重新登录
                            self.isAuthenticated = false
                            self.statusMessage = "Session expired, please sign in again"
                        }
                    }
                }
            }
        }
    }
}
