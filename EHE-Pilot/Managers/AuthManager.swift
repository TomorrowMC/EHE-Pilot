//
//  AuthManager.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/1/23.
//


import SwiftUI
import AppAuth

class AuthManager: ObservableObject {
    
    // 下面这些属性在实际项目中可放在安全的配置文件或 Keychain 中
    // 也可根据服务端提供的 .well-known JSON 动态获取
    private let issuerURL = URL(string: "https://20.115.48.58/o")!          // 你同伴给的 issuer
    private let clientID = "nChhwTBZ4SZJEg0QJftkWDkulGqIkIAsMLqXagFo"       // 你们实际的 client_id
    private let redirectURI = URL(string: "ehepilot://oauth/callback")!    // 你在 iOS 端的回调
    
    // 如果需要多个 scope，可用空格拼接，如 "openid profile email"
    private let defaultScopes = "openid"
    
    // AppAuth 对应的会话和授权信息
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    @Published var authState: OIDAuthState?   // 保存 Access Token/Refresh Token/ID Token 等
    
    /// 加载 Discovery 文档并启动授权请求
    func signIn() {
        // 第一步：获取配置（会去访问 issuerURL + /.well-known/openid-configuration）
        OIDAuthorizationService.discoverConfiguration(forIssuer: issuerURL) { configuration, error in
            if let error = error {
                print("发现 OIDC 配置出错: \(error)")
                return
            }
            guard let config = configuration else {
                print("配置为空")
                return
            }
            
            // 构造请求，使用 PKCE
            let codeVerifier = OIDAuthorizationRequest.generateCodeVerifier()
            let codeChallenge = OIDAuthorizationRequest.codeChallengeS256(forVerifier: codeVerifier)
            let codeChallengeMethod = OIDOAuthorizationRequestCodeChallengeMethodS256

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
                codeChallengeMethod: codeChallengeMethod,
                additionalParameters: nil
            )
            
            // 以 SFAuthenticationSession 或 ASWebAuthenticationSession 打开浏览器窗口
            guard let rootViewController = UIApplication.shared.windows.first?.rootViewController else {
                return
            }
            
            self.currentAuthorizationFlow =
            OIDAuthState.authState(byPresenting: request,
                                   presenting: rootViewController) { authState, error in
                if let authState = authState {
                    print("授权成功，获取到: \(authState.lastTokenResponse?.accessToken ?? "无 access token")")
                    self.authState = authState
                } else {
                    print("授权失败: \(error?.localizedDescription ?? "未知错误")")
                }
            }
        }
    }
    
    /// 处理应用通过 URL Scheme 回调的结果
    func handleRedirectURL(_ url: URL) -> Bool {
        if let flow = currentAuthorizationFlow,
           flow.resumeExternalUserAgentFlow(with: url) {
            currentAuthorizationFlow = nil
            return true
        }
        return false
    }
    
    /// 获取当前 Access Token
    func currentAccessToken() -> String? {
        return authState?.lastTokenResponse?.accessToken
    }
    
    /// 刷新 Token
    func refreshTokenIfNeeded(completion: @escaping (String?) -> Void) {
        authState?.setNeedsTokenRefresh()
        authState?.performAction() { accessToken, idToken, error in
            if let error = error {
                print("刷新 token 出错：\(error)")
                completion(nil)
                return
            }
            completion(accessToken)
        }
    }
}
