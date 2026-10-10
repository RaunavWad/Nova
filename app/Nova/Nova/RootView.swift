//
//  RootView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI

/// Launch flow: animation, then login (only if nobody is signed in and you haven't chosen to continue without),
/// then the app. A signed-in user (Firebase remembers them) goes straight from the animation to the home screen.
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
