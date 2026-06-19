import SwiftUI
import Supabase

@Observable
@MainActor
final class AuthManager {

    static let shared = AuthManager()

    var isAuthenticated = false
    var isLoading = false
    var isBootstrapping = true          // true while we restore a saved session on launch
    var errorMessage: String?
    var userEmail: String?

    private let auth = SupabaseConfig.client.auth

    private init() {}

    // MARK: - Launch: restore any saved session

    func bootstrap() async {
        defer { isBootstrapping = false }
        guard SupabaseConfig.isConfigured else { return }
        do {
            let session = try await auth.session
            applySignedIn(session.user.email)
        } catch {
            // No valid session — stay logged out, no error to show.
            isAuthenticated = false
        }
    }

    // MARK: - Email + password

    func signUp(email: String, password: String) async {
        guard validate(email: email, password: password) else { return }
        await run {
            let response = try await self.auth.signUp(email: email, password: password)
            // If email confirmations are ON, session is nil until the user confirms.
            if response.session != nil {
                self.applySignedIn(email)
            } else {
                self.errorMessage = "Check your inbox to confirm your email, then log in."
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard validate(email: email, password: password) else { return }
        await run {
            let session = try await self.auth.signIn(email: email, password: password)
            self.applySignedIn(session.user.email)
        }
    }

    // MARK: - Google (OAuth via Supabase)

    func signInWithGoogle() async {
        guard SupabaseConfig.isConfigured else {
            errorMessage = "Add your Supabase URL and anon key in SupabaseConfig.swift first."
            return
        }
        await run {
            let session = try await self.auth.signInWithOAuth(
                provider: .google,
                redirectTo: SupabaseConfig.redirectURL
            )
            self.applySignedIn(session.user.email)
        }
    }

    // MARK: - Sign out

    func signOut() {
        Task {
            try? await auth.signOut()
            isAuthenticated = false
            userEmail = nil
            errorMessage = nil
        }
    }

    // MARK: - Helpers

    /// Runs an async auth call with shared loading + error handling.
    private func run(_ work: @escaping () async throws -> Void) async {
        guard SupabaseConfig.isConfigured else {
            errorMessage = "Add your Supabase URL and anon key in SupabaseConfig.swift first."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await work()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func applySignedIn(_ email: String?) {
        userEmail = email
        isAuthenticated = true
        errorMessage = nil
    }

    private func validate(email: String, password: String) -> Bool {
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            return false
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return false
        }
        return true
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: regex, options: .regularExpression) != nil
    }

    private func friendlyMessage(for error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login") {
            return "Incorrect email or password."
        }
        if text.localizedCaseInsensitiveContains("already registered") {
            return "That email is already registered. Try logging in."
        }
        return text
    }
}
