import Combine
import Foundation
import SwiftUI
import UIKit
#if canImport(FirebaseAuth) && canImport(FirebaseCore) && canImport(GoogleSignIn)
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
#endif

/// Optional Google sign-in through Firebase Authentication.
/// Nova is fully usable without an account; signing in is never required. At the moment it only identifies you
/// (name and email shown in Settings). Progress still lives on this device. Nothing about your location, sky activity
/// or discoveries is sent to Firebase.
///
/// The Firebase and Google Sign-In packages are optional at build time: without them (or without a GoogleService-Info.plist)
/// the app compiles and runs normally and the Settings screen says sign-in is not set up.
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var displayName: String? = nil
    @Published private(set) var email: String? = nil
    @Published private(set) var isBusy = false
    @Published private(set) var message: String? = nil
    @Published private(set) var isAvailable = false

    init() {}

    /// First word of the Google account name, e.g. "Vihaan". Falls back to the start of the email address.
    var firstName: String? {
        if let n = displayName?.split(separator: " ").first, !n.isEmpty { return String(n) }
        if let e = email?.split(separator: "@").first, !e.isEmpty { return String(e) }
        return nil
    }

#if canImport(FirebaseAuth) && canImport(FirebaseCore) && canImport(GoogleSignIn)
    private var handle: AuthStateDidChangeListenerHandle?

    /// Call once at launch. Safe to call when Firebase isn't configured.
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

    func signInWithGoogle() async {
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

    /// Hands the redirect URL from the Google sign-in sheet back to the SDK.
    func handle(url: URL) { _ = GIDSignIn.sharedInstance.handle(url) }

#else
    func configure() { isAvailable = false }
    func signInWithGoogle() async { message = "Sign-in is not set up in this build." }
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
