import SwiftUI

struct RegisterView: View {
    var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var isValidEmail: Bool {
        NSPredicate(format: "SELF MATCHES %@", "[A-Z0-9a-z._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}")
            .evaluate(with: email)
    }
    private var isValidPassword: Bool { password.count >= 8 }
    private var passwordMismatch: Bool { !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword }
    private var canSubmit: Bool {
        !displayName.isEmpty && isValidEmail && isValidPassword && !passwordMismatch && !viewModel.isLoading
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        TextField(
                            "",
                            text: $displayName,
                            prompt: Text("Display name").foregroundStyle(AdaptiveColor.peOutline)
                        )
                        .textContentType(.name)
                        .textFieldStyle(.plain)
                        .peFieldStyle()

                        TextField(
                            "",
                            text: $email,
                            prompt: Text("Email").foregroundStyle(AdaptiveColor.peOutline)
                        )
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                        .textFieldStyle(.plain)
                        .peFieldStyle()

                        if !email.isEmpty && !isValidEmail {
                            Text("Enter a valid email address.")
                                .font(.peLabelSm())
                                .foregroundStyle(AdaptiveColor.peError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        SecureField(
                            "",
                            text: $password,
                            prompt: Text("Password").foregroundStyle(AdaptiveColor.peOutline)
                        )
                        .textContentType(.newPassword)
                        .peFieldStyle()

                        if !password.isEmpty && !isValidPassword {
                            Text("Password must be at least 8 characters.")
                                .font(.peLabelSm())
                                .foregroundStyle(AdaptiveColor.peError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        SecureField(
                            "",
                            text: $confirmPassword,
                            prompt: Text("Confirm password").foregroundStyle(AdaptiveColor.peOutline)
                        )
                        .textContentType(.password)
                        .peFieldStyle()

                        if passwordMismatch {
                            Text("Passwords do not match.")
                                .font(.peLabelSm())
                                .foregroundStyle(AdaptiveColor.peError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let error = viewModel.registerErrorMessage {
                        Text(error)
                            .font(.peLabelSm())
                            .foregroundStyle(AdaptiveColor.peError)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await viewModel.register(email: email, displayName: displayName, password: password) }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView().tint(AdaptiveColor.peOnPrimary)
                        } else {
                            Text("Create Account")
                        }
                    }
                    .buttonStyle(PEPrimaryButton())
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
        .peScreenBackground()
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.large)
        .peNavBar()
        .onChange(of: viewModel.isAuthenticated) { _, isAuth in
            if isAuth { dismiss() }
        }
    }
}

#Preview {
    NavigationStack {
        RegisterView(viewModel: AuthViewModel(
            authRepository: MockAuthRepository(),
            tokenStore: TokenStore()
        ))
    }
}
