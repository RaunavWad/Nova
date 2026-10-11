//
//  AuthManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Combine
import Foundation
import SwiftUI
import UIKit
#if canImport(FirebaseAuth) && canImport(FirebaseCore) && canImport(GoogleSignIn)
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
#endif

// the google sign in is optional

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var displayName: String? = nil
    @Published private(set) var email: String? = nil
    @Published private(set) var isBusy = false
    @Published private(set) var message: String? = nil
    @Published private(set) var isAvailable = false

    init() {}

    var firstName: String? {
        if let n = displayName?.split(separator: " ").first, !n.isEmpty { return String(n) }
        if let e = email?.split(separator: "@").first, !e.isEmpty { return String(e) }
        return nil
    }

#if canImport(FirebaseAuth) && canImport(FirebaseCore) && canImport(GoogleSignIn)
    private var handle: AuthStateDidChangeListenerHandle?

    func configure() {
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        guard FirebaseApp.app() != nil else { isAvailable = false; return }
        isAvailable = true
        apply(Auth.auth().currentUser)
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.apply(user) }
        }
    }

    private func apply(_ user: User?) {
        isSignedIn = user != nil
        displayName = user?.displayName
        email = user?.email
    }


        }
        return nil
    }

    func signInWithGoogle() async {
        // Starting Google sign-in without its URL scheme crashes the app, so check first.
        if let problem = setupProblem { message = problem; return }
        guard isAvailable, let clientID = FirebaseApp.app()?.options.clientID else {
            message = "Sign-in is not set up in this build."; return
        }
        guard let presenter = Self.topViewController() else { message = "Couldn't open the sign-in screen."; return }
        isBusy = true; message = nil
        defer { isBusy = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { message = "Google didn't return a sign-in token."; return }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            _ = try await Auth.auth().signIn(with: credential)
            message = "Signed in."
        } catch {
            let ns = error as NSError
            // -5 is the user cancelling the Google sheet; that is not an error worth announcing.
            message = (ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.canceled.rawValue)
                ? "Sign-in cancelled." : "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        message = "Signed out."
    }

    func handle(url: URL) { _ = GIDSignIn.sharedInstance.handle(url) }

    }
    func signInWithGoogle() async { message = setupProblem }
    func signOut() {}
    func handle(url: URL) {}
#endif

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
