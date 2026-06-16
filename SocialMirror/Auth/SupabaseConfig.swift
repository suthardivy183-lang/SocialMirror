import Foundation
import Supabase

/// Central Supabase client.
///
/// Fill in the two values below from your Supabase project dashboard:
///   Project Settings → Data API → Project URL  and  API Keys → `anon` `public`.
///
/// Both are safe to ship in a client app — the anon key is meant to be public
/// and is protected by Row Level Security on the server.
enum SupabaseConfig {

    /// e.g. "https://abcdefghijklmno.supabase.co"
    static let projectURL = "https://YOUR_PROJECT_REF.supabase.co"

    /// The `anon` / `public` key (a long JWT starting with "eyJ...").
    static let anonKey = "YOUR_ANON_PUBLIC_KEY"

    /// Custom URL scheme used for the Google OAuth redirect.
    /// Must match the URL Type you register in the target's Info settings.
    static let redirectURL = URL(string: "com.divy.socialmirror://login-callback")!

    /// True once the placeholders above have been replaced with real values.
    static var isConfigured: Bool {
        !projectURL.contains("YOUR_PROJECT_REF") && !anonKey.contains("YOUR_ANON")
    }

    static let client = SupabaseClient(
        supabaseURL: URL(string: projectURL)!,
        supabaseKey: anonKey
    )
}
