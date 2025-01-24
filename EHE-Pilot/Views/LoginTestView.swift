//
//  LoginTestView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/1/23.
//


import SwiftUI

struct LoginTestView: View {
    @EnvironmentObject var authManager: AuthManager  // 假设你已有AuthManager
    
    var body: some View {
        VStack(spacing: 20) {
            Text("OAuth 测试登录")
                .font(.title)
            
            Button("开始登录") {
                authManager.signIn()
            }
            .font(.headline)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            if let token = authManager.currentAccessToken() {
                Text("当前 Access Token: \(token)")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(.horizontal)
            } else {
                Text("尚未登录或 Token 已失效")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .navigationTitle("Login Test")
    }
}