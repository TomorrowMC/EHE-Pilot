import SwiftUI

struct TokenTestView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var refreshResult: String = ""
    @State private var showTokenDetails = false
    @State private var invitationLink: String = ""
    @State private var isLoading: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("邀请链接登录")) {
                TextField("粘贴邀请链接或授权码", text: $invitationLink)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Button(action: {
                    tryLoginWithInvitationLink()
                }) {
                    HStack {
                        Text("使用邀请链接登录")
                        if isLoading {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(invitationLink.isEmpty || isLoading)
                
                if !refreshResult.isEmpty {
                    Text(refreshResult)
                        .foregroundColor(refreshResult.contains("成功") ? .green : .red)
                        .padding(.vertical, 4)
                }
                
                // 添加说明
                VStack(alignment: .leading, spacing: 4) {
                    Text("提示:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("1. 您可以直接粘贴完整的邀请链接")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("2. 或者只粘贴邀请链接中的授权码部分")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("3. 系统会自动尝试多种可能的重定向URI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
            
            Section(header: Text("认证状态")) {
                HStack {
                    Text("已登录:")
                    Spacer()
                    Text(authManager.isAuthenticated ? "是" : "否")
                        .foregroundColor(authManager.isAuthenticated ? .green : .red)
                }
                
                if authManager.isAuthenticated {
                    Button("显示/隐藏令牌详情") {
                        showTokenDetails.toggle()
                    }
                    
                    if showTokenDetails, let tokenResponse = authManager.tokenResponse {
                        VStack(alignment: .leading, spacing: 8) {
                            if let accessToken = tokenResponse["access_token"] as? String {
                                Text("访问令牌:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(accessToken.prefix(20) + "..."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let refreshToken = tokenResponse["refresh_token"] as? String {
                                Text("刷新令牌:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(refreshToken.prefix(20) + "..."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let expiryDate = authManager.getTokenExpiry() {
                                Text("过期时间:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(expiryDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(expiryDate, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // 添加过期状态
                                let isExpired = Date() > expiryDate
                                HStack {
                                    Text("状态:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(isExpired ? "已过期" : "有效")
                                        .font(.caption)
                                        .foregroundColor(isExpired ? .red : .green)
                                }
                            }
                            
                            // 添加用户信息显示
                            if let profileData = authManager.profileData {
                                Divider()
                                
                                Text("用户信息:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if let id = profileData["id"] as? Int {
                                    Text("ID: \(id)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let email = profileData["email"] as? String {
                                    Text("邮箱: \(email)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let firstName = profileData["firstName"] as? String,
                                   let lastName = profileData["lastName"] as? String {
                                    Text("姓名: \(lastName) \(firstName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let patient = profileData["patient"] as? [String: Any],
                                   let patientId = patient["id"] as? Int {
                                    Text("患者ID: \(patientId)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            
            Section(header: Text("令牌测试")) {
                Button("验证令牌") {
                    authManager.verifyTokenValidity { isValid in
                        refreshResult = isValid ? "令牌有效" : "令牌无效或已过期"
                    }
                }
                
                Button("强制刷新令牌") {
                    authManager.refreshTokenWithStoredRefreshToken { success in
                        refreshResult = success ? "令牌刷新成功" : "令牌刷新失败"
                    }
                }
                
                Button("从存储加载令牌") {
                    let success = authManager.loadTokensFromStorage()
                    refreshResult = success ? "已从存储加载令牌" : "加载令牌失败"
                }
                
                Button("清除存储的令牌") {
                    authManager.clearStoredTokens()
                    refreshResult = "已清除存储的令牌"
                }
                
                Button("同步当前令牌到钥匙串") {
                    let success = authManager.syncCurrentTokensToKeyChain()
                    refreshResult = success ? "成功同步令牌到钥匙串" : "同步令牌失败"
                }
            }
            
            Section(header: Text("自动登录测试")) {
                Button("测试自动登录") {
                    if authManager.isAuthenticated {
                        authManager.signOut()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            AppDelegate.shared.attemptAutoLogin()
                            refreshResult = "自动登录测试已启动"
                        }
                    } else {
                        AppDelegate.shared.attemptAutoLogin()
                        refreshResult = "自动登录测试已启动"
                    }
                }
            }
        }
        .navigationTitle("令牌测试")
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("提示"),
                message: Text(alertMessage),
                dismissButton: .default(Text("确定"))
            )
        }
    }
    
    private func tryLoginWithInvitationLink() {
        guard !invitationLink.isEmpty else {
            showAlert(message: "请输入邀请链接或授权码")
            return
        }
        
        isLoading = true
        refreshResult = "正在解析邀请链接..."
        
        // 解析邀请链接
        if let authCode = authManager.parseInvitationLink(url: invitationLink) {
            refreshResult = "已提取授权码: \(authCode.prefix(5))..."
            
            // 使用授权码登录
            authManager.loginWithAuthorizationCode(code: authCode) { success in
                isLoading = false
                
                if success {
                    refreshResult = "使用邀请链接登录成功！"
                    invitationLink = "" // 清空输入框
                } else {
                    refreshResult = "使用邀请链接登录失败，请检查链接是否有效"
                    showAlert(message: "登录失败。可能的原因：\n1. 邀请链接已过期或无效\n2. 服务器配置问题\n3. 网络连接问题\n\n请尝试获取新的邀请链接或联系管理员。")
                }
            }
        } else {
            isLoading = false
            refreshResult = "无法从链接中提取授权码，请检查链接格式"
            showAlert(message: "无法从您输入的文本中提取授权码。请确保您输入了完整的邀请链接或正确的授权码。")
        }
    }
    
    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
}
