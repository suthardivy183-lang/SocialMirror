import SwiftUI
import AuthenticationServices

struct AuthView: View {

    @State private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    private enum Field { case email, password }
    @FocusState private var focusedField: Field?

    // MARK: - Palette (dark, OpenAI-inspired)
    private let bgColor       = Color(hex: "0A0A0A")
    private let inputBg       = Color(hex: "141414")
    private let borderNormal  = Color(hex: "2A2A2A")
    private let secondaryText = Color(hex: "888888")

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 64)

                    logoMark

                    Spacer().frame(height: 40)

                    titleText

                    Spacer().frame(height: 32)

                    VStack(spacing: 14) {
                        emailField
                        passwordField
                        continueButton
                        toggleLink
                    }

                    Spacer().frame(height: 28)

                    orDivider

                    Spacer().frame(height: 28)

                    VStack(spacing: 12) {
                        googleButton
                        appleButton
                    }

                    Spacer().frame(height: 48)

                    footerLinks

                    Spacer().frame(height: 32)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .alert("Error", isPresented: Binding(
            get: { authManager.errorMessage != nil },
            set: { if !$0 { authManager.errorMessage = nil } }
        )) {
            Button("OK") { authManager.errorMessage = nil }
        } message: {
            Text(authManager.errorMessage ?? "")
        }
    }

    // MARK: - Logo

    private var logoMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColor.primary.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColor.primary.opacity(0.25), lineWidth: 1)
                )
                .frame(width: 60, height: 60)

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(AppColor.primary)
        }
    }

    // MARK: - Title

    private var titleText: some View {
        VStack(spacing: 8) {
            Text(isSignUp ? "Create an account" : "Welcome back")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Email field

    private var emailField: some View {
        TextField("", text: $email, prompt:
            Text("Email address")
                .foregroundColor(secondaryText)
        )
        .font(.system(size: 16))
        .foregroundStyle(.white)
        .keyboardType(.emailAddress)
        .textContentType(.username)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.next)
        .focused($focusedField, equals: .email)
        .onSubmit { focusedField = .password }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(focusedField == .email ? AppColor.primary : borderNormal, lineWidth: 1.5)
        )
        .animation(AppAnim.snappy, value: focusedField)
    }

    // MARK: - Password field

    private var passwordField: some View {
        SecureField("", text: $password, prompt:
            Text("Password")
                .foregroundColor(secondaryText)
        )
        .font(.system(size: 16))
        .foregroundStyle(.white)
        .textContentType(isSignUp ? .newPassword : .password)
        .submitLabel(.go)
        .focused($focusedField, equals: .password)
        .onSubmit(submit)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(focusedField == .password ? AppColor.primary : borderNormal, lineWidth: 1.5)
        )
        .animation(AppAnim.snappy, value: focusedField)
    }

    // MARK: - Continue button

    private var continueButton: some View {
        Button(action: submit) {
            ZStack {
                if authManager.isLoading {
                    ProgressView()
                        .tint(Color(hex: "0A0A0A"))
                        .scaleEffect(0.85)
                } else {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "0A0A0A"))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .disabled(authManager.isLoading || !canSubmit)
        .opacity(canSubmit ? 1 : 0.5)
        .animation(AppAnim.snappy, value: canSubmit)
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            if isSignUp {
                await authManager.signUp(email: email, password: password)
            } else {
                await authManager.signIn(email: email, password: password)
            }
        }
    }

    // MARK: - Toggle link

    private var toggleLink: some View {
        HStack(spacing: 4) {
            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                .font(.system(size: 14))
                .foregroundStyle(secondaryText)

            Button(isSignUp ? "Log in" : "Sign up") {
                withAnimation(AppAnim.standard) {
                    isSignUp.toggle()
                    password = ""
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(AppColor.primary)
        }
    }

    // MARK: - OR divider

    private var orDivider: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(borderNormal)
                .frame(height: 1)
            Text("OR")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(secondaryText)
            Rectangle()
                .fill(borderNormal)
                .frame(height: 1)
        }
    }

    // MARK: - Google button

    private var googleButton: some View {
        Button {
            Task { await authManager.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                GoogleGMark()
                    .frame(width: 20, height: 20)

                Text("Continue with Google")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderNormal, lineWidth: 1)
            )
        }
    }

    // MARK: - Apple button

    private var appleButton: some View {
        SignInWithAppleButton(isSignUp ? .signUp : .signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            Task { await authManager.handleAppleSignIn(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderNormal, lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footerLinks: some View {
        HStack(spacing: 0) {
            Button("Terms of Use") {}
                .font(.system(size: 12))
                .foregroundStyle(secondaryText)

            Text("  |  ")
                .font(.system(size: 12))
                .foregroundStyle(secondaryText.opacity(0.4))

            Button("Privacy Policy") {}
                .font(.system(size: 12))
                .foregroundStyle(secondaryText)
        }
    }
}

// MARK: - Google G mark

/// Four-colour ring that approximates the Google G logo.
/// Replace with an actual SVG/PNG asset from your brand kit for production.
private struct GoogleGMark: View {

    private struct Arc: Identifiable {
        let id = UUID()
        let color: Color
        let start: Double
        let end: Double
    }

    private let arcs: [Arc] = [
        Arc(color: Color(hex: "4285F4"), start: -60, end:  60),   // blue  (top-right)
        Arc(color: Color(hex: "34A853"), start:  60, end: 150),   // green (bottom-right)
        Arc(color: Color(hex: "FBBC05"), start: 150, end: 235),   // yellow(bottom-left)
        Arc(color: Color(hex: "EA4335"), start: 235, end: 300),   // red   (top-left)
    ]

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let outerR = min(cx, cy)
            let stroke  = outerR * 0.42

            for arc in arcs {
                var path = Path()
                path.addArc(
                    center: CGPoint(x: cx, y: cy),
                    radius: outerR - stroke / 2,
                    startAngle: .degrees(arc.start),
                    endAngle:   .degrees(arc.end),
                    clockwise: false
                )
                ctx.stroke(
                    path,
                    with: .color(arc.color),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .butt)
                )
            }

            // Horizontal tab (the cross-bar of the "G") — blue
            let tabY   = cy - stroke / 2
            let tabX   = cx
            let tabW   = outerR - stroke * 0.1
            var tab    = Path()
            tab.addRect(CGRect(x: tabX, y: tabY, width: tabW, height: stroke))
            ctx.fill(tab, with: .color(Color(hex: "4285F4")))
        }
    }
}

#Preview {
    AuthView()
}
