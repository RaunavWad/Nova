//
//  LoginView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//


import SwiftUI

struct LoginView: View {
    var onSkip: () -> Void

    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var haptics: HapticsManager

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 22) {
                Spacer(minLength: 20)

                Image(systemName: "sparkle")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)

                Text("Nova")
                    .font(AppFont.serif(size: 56))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)

                Text("Sign in with Google and Nova will greet you by name. Everything works without an account.")
                    .font(AppFont.style(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 20)

                VStack(spacing: 12) {
                    Button {
                        Task { await signIn() }
                    } label: {
                        Label("Continue with Google", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(BigButtonStyle())
                    .disabled(auth.isBusy)
                    .accessibilityHint("Opens the Google sign-in screen")

                    Button {
                        haptics.play(.select)
                        onSkip()
                    } label: {
                        Text("Continue without signing in")
                    }
                    .buttonStyle(BigButtonStyle(prominent: false))

                    if auth.isBusy { ProgressView().tint(Theme.accent) }

                    if let problem = auth.setupProblem {
                        Text(problem + " You can continue without it.")
                            .font(AppFont.style(.footnote))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    if let m = auth.message {
                        Text(m)
                            .font(AppFont.style(.footnote))
                            .foregroundStyle(Theme.violet)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
        .onAppear {
            speech.announce("Welcome to Nova. Continue with Google, or continue without signing in.")
        }
    }

    private func signIn() async {
        haptics.play(.select)
        await auth.signInWithGoogle()
        if let m = auth.message { speech.announce(m) }
    }
}
