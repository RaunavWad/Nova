//
//  RootView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI


struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @AppStorage("novaContinuedWithoutLogin") private var continuedWithoutLogin = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
                }
                .transition(.opacity)
            } else if !auth.isSignedIn && !continuedWithoutLogin {
                LoginView {
                    withAnimation(.easeInOut(duration: 0.4)) { continuedWithoutLogin = true }
                }
                .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .background(Theme.midnight.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.4), value: auth.isSignedIn)
    }
}
