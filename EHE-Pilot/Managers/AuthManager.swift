//AuthManager.swift
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

    func getTokenExpiry() -> Date? {
        if let timestamp = UserDefaults.standard.object(forKey: tokenExpiryKey) as? TimeInterval {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }

    // 修改saveTokens方法，不再强制使用两周过期时间
    func saveTokens(accessToken: String, refreshToken: String, expiresIn: TimeInterval) {
        // 保存token到KeyChain
        saveTokenToKeychain(token: accessToken, forKey: accessTokenKey)
        saveTokenToKeychain(token: refreshToken, forKey: refreshTokenKey)
        
        // 使用服务器提供的过期时间
        let expiryDate = Date().addingTimeInterval(expiresIn)
        
        // 打印调试信息
        print("设置Token过期时间，当前时间: \(Date())")
        print("服务器提供的过期参数: \(expiresIn) 秒")
        print("计算的过期时间: \(expiryDate)")
        
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
        print("尝试从KeyChain加载Token...")
        
        // 打印是否存在Token
        if let accessToken = loadTokenFromKeychain(forKey: accessTokenKey) {
            print("发现访问Token: \(accessToken.prefix(10))...")
        } else {
            print("KeyChain中没有访问Token")
        }
        
        if let refreshToken = loadTokenFromKeychain(forKey: refreshTokenKey) {
            print("发现刷新Token: \(refreshToken.prefix(10))...")
        } else {
            print("KeyChain中没有刷新Token")
        }
        
        guard let accessToken = loadTokenFromKeychain(forKey: accessTokenKey),
              let refreshToken = loadTokenFromKeychain(forKey: refreshTokenKey) else {
            print("无法从KeyChain加载完整Token")
            return false
        }
        
        // 恢复token状态
        self.tokenResponse = [
            "access_token": accessToken,
            "refresh_token": refreshToken
        ]
        
        // 检查是否过期
        if let expiryDate = getTokenExpiry() {
            print("Token过期时间: \(expiryDate)")
            if expiryDate > Date() {
                self.isAuthenticated = true
                print("Token未过期，设置为已认证")
                return true
            } else {
                print("Token已过期，需要刷新")
                // 即使过期也返回true，因为我们有refreshToken可以尝试刷新
                return true
            }
        } else {
            print("找不到Token过期时间")
            // 如果没有过期时间但有Token，仍然可以尝试使用
            self.isAuthenticated = true
            return true
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

    // 修改signOut方法末尾
    func signOut() {
        authState = nil
        tokenResponse = nil
        profileData = nil
        isAuthenticated = false
        statusMessage = "Signed out"
        
        // 清除所有存储的Token
        deleteAuthStateFromKeychain()
        clearStoredTokens()
    }

    // 增加同步OIDAuthState和自定义Token存储的方法
    private func syncTokensFromAuthState() {
        if let authState = self.authState,
           let tokenResponse = authState.lastTokenResponse,
           let accessToken = tokenResponse.accessToken,
           let refreshToken = tokenResponse.refreshToken {
            let expiresIn = tokenResponse.accessTokenExpirationDate?.timeIntervalSinceNow ?? 1209600
            self.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        }
    }

    // 添加自动登录方法
    func attemptAutoLogin(completion: @escaping (Bool) -> Void) {
        print("尝试自动登录...")
        
        // 先尝试从KeyChain加载Token
        if loadTokensFromStorage() {
            print("从KeyChain加载到Token")
            
            // 已从KeyChain加载Token，设置为已认证状态
            self.isAuthenticated = true
            
            // 获取用户资料
            fetchUserProfile { success in
                if success {
                    print("获取用户资料成功")
                    
                    // 开始Token自动刷新
                    TokenRefreshManager.shared.startAutoRefresh()
                    
                    completion(true)
                } else {
                    print("获取用户资料失败，但仍保持登录状态")
                    
                    // 获取资料失败但仍保持登录状态
                    completion(true)
                    
                    // 尝试刷新Token
                    self.refreshTokenWithStoredRefreshToken { _ in }
                }
            }
        } else {
            // KeyChain中没有Token
            print("KeyChain中没有Token，无法自动登录")
            completion(false)
        }
    }
    
    // 使用存储的refreshToken刷新accessToken
    // 改进刷新Token机制
    // 改进刷新Token机制
    func refreshTokenWithStoredRefreshToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = loadTokenFromKeychain(forKey: refreshTokenKey) else {
            print("No refresh token found in keychain")
            completion(false)
            return
        }
        
        // 如果discoveryConfig为空，先尝试加载配置
        // 如果discoveryConfig为空，先尝试加载配置
        if discoveryConfig == nil {
            discoverConfiguration { [weak self] success in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                if !success {
                    DispatchQueue.main.async {
                        // 配置失败不应该导致登出
                        print("Failed to discover configuration")
                        // 仍然认为认证有效，避免登出
                        completion(true)
                    }
                    return
                }
                
                // 再次调用自身，此时已有配置
                self.refreshTokenWithStoredRefreshToken(completion: completion)
            }
            return
        }
        
        guard let tokenEndpoint = discoveryConfig?["token_endpoint"] as? String,
              let tokenURL = URL(string: tokenEndpoint) else {
            print("Missing token endpoint in discovered configuration")
            // 配置问题不应该导致登出
            completion(true)
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
                    // 网络错误不应导致登出
                    completion(true)
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid token refresh response")
                    self.statusMessage = "Invalid token refresh response"
                    // 网络问题不应导致登出
                    completion(true)
                    return
                }
                
                // 只有明确的401/403才认为刷新失败
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    print("Refresh token is invalid")
                    self.statusMessage = "Refresh token is invalid"
                    completion(false)
                    return
                }
                
                // 正常200响应
                if httpResponse.statusCode == 200 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let accessToken = json["access_token"] as? String {
                            // 保存新的token
                            let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
                            let expiresIn = json["expires_in"] as? TimeInterval ?? 3600
                            
                            print("服务器返回的过期时间: \(expiresIn) 秒")
                            
                            // 使用服务器返回的过期时间
                            self.saveTokens(accessToken: accessToken, refreshToken: newRefreshToken, expiresIn: expiresIn)
                            self.statusMessage = "Token refreshed successfully"
                            completion(true)
                        } else {
                            print("Could not parse token refresh response")
                            self.statusMessage = "Could not parse token refresh response"
                            // 解析问题不应导致登出
                            completion(true)
                        }
                    } catch {
                        print("Error parsing token refresh response: \(error.localizedDescription)")
                        self.statusMessage = "Error parsing token refresh response"
                        // 解析错误不应导致登出
                        completion(true)
                    }
                } else {
                    // 其他HTTP错误
                    print("Unexpected status code: \(httpResponse.statusCode)")
                    // 不确定的错误，保持认证状态
                    completion(true)
                }
            }
        }
        
        task.resume()
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
                    // 在AuthManager.swift中修改signIn方法的回调部分
                    // 修改signIn方法中的成功回调部分
                    if let authState = authState {
                        self.authState = authState
                        self.isAuthenticated = true
                        self.statusMessage = "Authentication successful"
                        
                        // Save auth state to keychain
                        self.saveAuthStateToKeychain()
                        
                        // Extract token response data and save tokens
                        if let tokenResponse = authState.lastTokenResponse {
                            var tokenData: [String: Any] = [:]
                            if let accessToken = tokenResponse.accessToken {
                                tokenData["access_token"] = accessToken
                                
                                // 保存tokens到KeyChain
                                if let refreshToken = tokenResponse.refreshToken {
                                    print("将OAuth流程获取的Token保存到KeyChain")
                                    let expiresIn = tokenResponse.accessTokenExpirationDate?.timeIntervalSinceNow ?? 1209600
                                    self.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
                                }
                            }
                            
                            // 更新tokenResponse
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
                // 在loadAuthStateFromKeychain方法中的成功恢复authState后添加
                if let authState = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? OIDAuthState {
                    self.authState = authState
                    self.isAuthenticated = true
                    
                    // Extract token response data
                    if let tokenResponse = authState.lastTokenResponse {
                        var tokenData: [String: Any] = [:]
                        if let accessToken = tokenResponse.accessToken {
                            tokenData["access_token"] = accessToken
                            
                            // 同步Token到KeyChain
                            if let refreshToken = tokenResponse.refreshToken {
                                print("同步OIDAuthState中的Token到KeyChain")
                                // 强制使用两周(1209600秒)而不是服务器返回的时间
                                self.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: 1209600)
                            }
                        }
                        
                        // 更新tokenResponse属性
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
    

    // 解析邀请链接并提取授权码
    func parseInvitationLink(url: String) -> String? {
        guard !url.isEmpty else {
            print("URL为空")
            return nil
        }
        
        print("尝试解析邀请链接: \(url)")
        
        // 直接检查URL是否已经是一个授权码
        if url.count >= 8 && url.count <= 64 && !url.contains(" ") && !url.contains("http") {
            print("URL可能已经是授权码: \(url)")
            return url
        }
        
        // 尝试提取链接中的授权码
        
        // 检查是否包含cloud_sharing_code
        if url.contains("cloud_sharing_code=") {
            if let range = url.range(of: "cloud_sharing_code=") {
                let startIndex = range.upperBound
                var code = String(url[startIndex...])
                
                // 如果URL还有其他参数，只取到&之前的部分
                if let endIndex = code.firstIndex(of: "&") {
                    code = String(code[..<endIndex])
                }
                
                // 如果代码包含域名，提取后半部分
                if let separatorIndex = code.firstIndex(of: "|") {
                    let extractedCode = String(code[code.index(after: separatorIndex)...])
                    print("从cloud_sharing_code中提取的授权码: \(extractedCode)")
                    return extractedCode
                }
                
                print("从URL中提取的完整授权码: \(code)")
                return code
            }
        }
        
        // 尝试将URL解析为URLComponents
        guard let url = URL(string: url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("无法解析URL为组件")
            return nil
        }
        
        // 检查查询参数
        if let queryItems = components.queryItems {
            // 查找code参数
            if let codeItem = queryItems.first(where: { $0.name == "code" }) {
                print("从code参数中提取的授权码: \(codeItem.value ?? "")")
                return codeItem.value
            }
            
            // 查找referrer参数
            if let referrerItem = queryItems.first(where: { $0.name == "referrer" }) {
                guard let value = referrerItem.value else { return nil }
                
                if value.contains("cloud_sharing_code=") {
                    if let range = value.range(of: "cloud_sharing_code=") {
                        let startIndex = range.upperBound
                        let code = String(value[startIndex...])
                        
                        // 如果代码包含域名，提取后半部分
                        if let separatorIndex = code.firstIndex(of: "|") {
                            let extractedCode = String(code[code.index(after: separatorIndex)...])
                            print("从referrer参数中提取的授权码: \(extractedCode)")
                            return extractedCode
                        }
                        
                        print("从referrer参数中提取的完整授权码: \(code)")
                        return code
                    }
                }
            }
        }
        
        // 如果上面的方法都失败，尝试从完整URL中匹配最后一个路径组件
        let urlString = url.absoluteString
        if let lastComponent = urlString.split(separator: "/").last {
            let potentialCode = String(lastComponent)
            
            // 如果最后一个组件看起来像授权码（长度适中且没有特殊字符）
            if potentialCode.count >= 8 && potentialCode.count <= 64 &&
               potentialCode.rangeOfCharacter(from: CharacterSet(charactersIn: "?&=")) == nil {
                print("从URL路径中提取的可能授权码: \(potentialCode)")
                return potentialCode
            }
        }
        
        print("无法从URL中提取授权码")
        return nil
    }

    // 使用授权码登录
    func loginWithAuthorizationCode(code: String, completion: @escaping (Bool) -> Void) {
        // 确保已经发现了配置信息
        if discoveryConfig == nil {
            discoverConfiguration { [weak self] success in
                guard let self = self, success else {
                    DispatchQueue.main.async {
                        self?.statusMessage = "无法发现配置信息"
                        completion(false)
                    }
                    return
                }
                
                // 现在已有配置信息，递归调用
                self.loginWithAuthorizationCode(code: code, completion: completion)
            }
            return
        }
        
        // 获取令牌端点
        guard let tokenEndpoint = discoveryConfig?["token_endpoint"] as? String,
              let tokenURL = URL(string: tokenEndpoint) else {
            statusMessage = "缺少令牌端点"
            completion(false)
            return
        }
        
        // 准备请求数据
        let staticCodeVerifier = "f28984eaebcf41d881223399fc8eab27eaa374a9a8134eb3a900a3b7c0e6feab5b427479f3284ebe9c15b698849b0de2"
        
        // 可能的重定向URI列表（按可能性排序）
        let possibleRedirectURIs = [
            "https://ehepilot.com/auth/callback",
            "ehepilot://oauth/callback",
            "https://ehepilot.com",
            "https://ehepilot.com/o/auth/callback",
            "" // 空URI作为最后尝试
        ]
        
        // 尝试使用第一个重定向URI
        tryNextRedirectURI(index: 0, possibleURIs: possibleRedirectURIs)
        
        // 递归尝试不同的重定向URI
        func tryNextRedirectURI(index: Int, possibleURIs: [String]) {
            // 如果已经尝试了所有可能的URI，则失败
            if index >= possibleURIs.count {
                DispatchQueue.main.async {
                    self.statusMessage = "所有可能的重定向URI都失败了"
                    completion(false)
                }
                return
            }
            
            // 使用当前索引的重定向URI
            let redirectURI = possibleURIs[index]
            print("尝试使用重定向URI: \(redirectURI)")
            
            // 构建请求参数
            let parameters = [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": clientID,
                "code_verifier": staticCodeVerifier
            ]
            
            var request = URLRequest(url: URL(string: tokenEndpoint)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            // 转换参数为表单编码字符串
            let formString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = formString.data(using: .utf8)
            
            print("发送令牌请求，参数: \(formString)")
            
            // 发送请求
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("令牌交换错误: \(error.localizedDescription)")
                    // 尝试下一个重定向URI
                    DispatchQueue.main.async {
                        tryNextRedirectURI(index: index + 1, possibleURIs: possibleURIs)
                    }
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse else {
                    print("无效的令牌响应")
                    // 尝试下一个重定向URI
                    DispatchQueue.main.async {
                        tryNextRedirectURI(index: index + 1, possibleURIs: possibleURIs)
                    }
                    return
                }
                
                // 打印响应信息以进行调试
                print("令牌请求响应状态码: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("响应内容: \(responseString)")
                }
                
                // 检查是否需要尝试下一个重定向URI
                if httpResponse.statusCode == 400 {
                    let responseString = String(data: data, encoding: .utf8) ?? ""
                    if responseString.contains("Mismatching redirect URI") ||
                       responseString.contains("invalid_request") {
                        print("重定向URI不匹配，尝试下一个")
                        DispatchQueue.main.async {
                            tryNextRedirectURI(index: index + 1, possibleURIs: possibleURIs)
                        }
                        return
                    }
                }
                
                // 检查状态码
                if httpResponse.statusCode == 200 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            DispatchQueue.main.async {
                                self.tokenResponse = json
                                
                                // 提取访问令牌和刷新令牌
                                if let accessToken = json["access_token"] as? String,
                                   let refreshToken = json["refresh_token"] as? String {
                                    
                                    // 提取过期时间，如果没有则使用默认值
                                    let expiresIn = json["expires_in"] as? TimeInterval ?? 3600
                                    
                                    // 保存令牌到KeyChain
                                    self.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
                                    
                                    self.isAuthenticated = true
                                    self.statusMessage = "授权码登录成功"
                                    
                                    // 获取用户资料
                                    self.fetchUserProfile { _ in }
                                    
                                    // 记录成功的重定向URI，以便将来使用
                                    print("成功使用重定向URI: \(redirectURI)")
                                    UserDefaults.standard.set(redirectURI, forKey: "lastSuccessfulRedirectURI")
                                    
                                    completion(true)
                                } else {
                                    print("响应中缺少令牌")
                                    self.statusMessage = "响应中缺少令牌"
                                    completion(false)
                                }
                            }
                        } else {
                            print("无法解析令牌响应")
                            // 尝试下一个重定向URI
                            DispatchQueue.main.async {
                                tryNextRedirectURI(index: index + 1, possibleURIs: possibleURIs)
                            }
                        }
                    } catch {
                        print("解析令牌响应错误: \(error.localizedDescription)")
                        // 尝试下一个重定向URI
                        DispatchQueue.main.async {
                            tryNextRedirectURI(index: index + 1, possibleURIs: possibleURIs)
                        }
                    }
                } else {
                    print("令牌请求失败，状态码: \(httpResponse.statusCode)")
                    // 尝试下一个重定向URI
                    DispatchQueue.main.async {
                        tryNextRedirectURI(index: index + 1, possibleURIs: possibleURIs)
                    }
                }
            }
            
            task.resume()
        }
    }
    
    
    func syncCurrentTokensToKeyChain() -> Bool {
        if let accessToken = currentAccessToken(),
           let refreshToken = tokenResponse?["refresh_token"] as? String {
            // 从tokenResponse中获取过期时间，如果没有则默认1小时
            let expiresIn =  1296000  // 默认1小时
            saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: TimeInterval(expiresIn))
            print("成功将当前Token同步到KeyChain")
            return true
        } else if let authState = self.authState,
                  let tokenResponse = authState.lastTokenResponse,
                  let accessToken = tokenResponse.accessToken,
                  let refreshToken = tokenResponse.refreshToken {
            let expiresIn = tokenResponse.accessTokenExpirationDate?.timeIntervalSinceNow ?? 1209600
            saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
            print("成功将AuthState中的Token同步到KeyChain")
            return true
        }
        
        print("没有找到可用的Token来同步")
        return false
    }
    func verifyTokenValidity(completion: @escaping (Bool) -> Void) {
        // 先检查token是否过期
        if let expiryDate = getTokenExpiry(), expiryDate > Date() {
            // Token未过期，但仍然进行一次轻量级API请求验证
            // 如果API请求失败，仍然认为token有效，避免网络问题导致登出
            makeValidationRequest { isValid in
                // 只有当API明确返回401/403时才认为无效
                completion(isValid)
            }
        } else if let refreshToken = loadTokenFromKeychain(forKey: refreshTokenKey) {
            // Token过期但有刷新token，直接尝试刷新
            refreshTokenWithStoredRefreshToken { success in
                completion(success)
            }
        } else {
            // 没有token或刷新token
            completion(false)
        }
    }

    // 新增方法，只进行轻量级API请求验证
    private func makeValidationRequest(completion: @escaping (Bool) -> Void) {
        guard let accessToken = currentAccessToken() else {
            completion(false)
            return
        }
        
        let baseURLString = issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        guard let url = URL(string: "\(baseURLString)/api/v1/users/profile") else {
            completion(true) // 网络问题不会导致登出
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
                    // 网络错误不应该导致登出
                    completion(true)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(true) // 没有HTTP响应也不应该导致登出
                    return
                }
                
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    // 明确是认证错误
                    print("Token invalid - status code: \(httpResponse.statusCode)")
                    self.isAuthenticated = false
                    completion(false)
                } else {
                    // 其他情况都认为有效
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.profileData = json
                    }
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
