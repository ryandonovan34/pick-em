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
        // A real Form (not a plain VStack) — iOS's AutoFill form-detection
        // heuristics for the "Suggest Strong Password" UI are documented to
        // behave more reliably inside a genuine Form/Section structure.
        Form {
            Section {
                TextField(
                    "",
                    text: $displayName,
                    prompt: Text("Display name").foregroundStyle(AdaptiveColor.peOutline)
                )
                .textContentType(.name)
                .textFieldStyle(.plain)
                .peFieldStyle()

                VStack(alignment: .leading, spacing: 6) {
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
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
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
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SecureField(
                        "",
                        text: $confirmPassword,
                        prompt: Text("Confirm password").foregroundStyle(AdaptiveColor.peOutline)
                    )
                    // Deliberately no textContentType: pairing this field as
                    // .newPassword reintroduces the AutoFill sync/clearing loop,
                    // and .password surfaces an unrelated OLD saved credential —
                    // either way misleading for a field whose job is confirming
                    // what was just typed above.
                    .textContentType(nil)
                    .peFieldStyle()

                    if passwordMismatch {
                        Text("Passwords do not match.")
                            .font(.peLabelSm())
                            .foregroundStyle(AdaptiveColor.peError)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))

            if let error = viewModel.registerErrorMessage {
                Section {
                    Text(error)
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peError)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
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
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 6, trailing: 24))
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveColor.peBackground)
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
