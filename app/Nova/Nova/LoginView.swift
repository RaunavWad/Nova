//
//  LoginView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//


import SwiftUI

/// Shown after the launch animation when nobody is signed in. Signing in is optional: "Continue without signing in"
/// always works, so blind users and anyone without a Google account are never blocked.
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

                NovaMark(size: 96)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 24)

                Text("nova")
                    .font(AppFont.sans(size: 52, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-2)
                    .foregroundStyle(Theme.text)
                    .accessibilityLabel("Nova")
                    .accessibilityAddTraits(.isHeader)

                Text("The universe is for everyone.")
                    .font(AppFont.serif(size: 24, relativeTo: .title2))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)

                Text("Sign in with Google and Nova will greet you by name. Everything works without an account.")
                    .font(AppFont.style(.footnote))
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
