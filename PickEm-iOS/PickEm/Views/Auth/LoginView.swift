import SwiftUI

struct LoginView: View {
    enum FocusedField {
        case email
        case password
    }
    
    var viewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false
    @FocusState private var focusedField: FocusedField?

    private var isValidEmail: Bool {
        NSPredicate(format: "SELF MATCHES %@", "[A-Z0-9a-z._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}")
            .evaluate(with: email)
    }
    private var isValidPassword: Bool { password.count >= 8 }
    private var canSubmit: Bool { isValidEmail && isValidPassword && !viewModel.isLoading }
    
    @State private var shouldShowEmailError: Bool = false
    @State private var shouldShowPasswordError: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    Spacer()

                    // Logo
                    VStack(spacing: 6) {
                        Text("PICKEM")
                            .font(.peDisplay())
                            .foregroundStyle(AdaptiveColor.pePrimaryFill)
                            .tracking(-1)
                        Text("PICK GAMES. BEAT YOUR FRIENDS.")
                            .font(.peLabelBold())
                            .tracking(2)
                            .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                    }
                    .padding(.bottom, 48)

                    // Fields
                    VStack(spacing: 12) {
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
                        .focused($focusedField, equals: .email)
                        .onSubmit {
                            focusedField = .password
                        }
                        .onChange(of: email) { _, newValue in
                            if shouldShowEmailError {
                                shouldShowEmailError = !email.isEmpty && !isValidEmail
                            }
                        }
                        .onChange(of: focusedField) { oldValue, newValue in
                            if oldValue == .email && newValue != .email {
                                shouldShowEmailError = !email.isEmpty && !isValidEmail
                            }
                        }

                        if shouldShowEmailError {
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
                        .textContentType(.password)
                        .peFieldStyle()
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            focusedField = nil
                            Task { await viewModel.login(email: email, password: password) }
                        }
                        .onChange(of: password) { _, newValue in
                            if shouldShowPasswordError {
                                shouldShowPasswordError = !password.isEmpty && !isValidPassword
                            }
                        }
                        .onChange(of: focusedField) { oldValue, newValue in
                            if oldValue == .password && newValue != .password {
                                shouldShowPasswordError = !password.isEmpty && !isValidPassword
                            }
                        }

                        if shouldShowPasswordError {
                            Text("Password must be at least 8 characters.")
                                .font(.peLabelSm())
                                .foregroundStyle(AdaptiveColor.peError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)

                    if let error = viewModel.loginErrorMessage {
                        Text(error)
                            .font(.peLabelSm())
                            .foregroundStyle(AdaptiveColor.peError)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }

                    Button {
                        Task { await viewModel.login(email: email, password: password) }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView().tint(AdaptiveColor.peOnPrimary)
                        } else {
                            Text("Sign In")
                        }
                    }
                    .buttonStyle(PEPrimaryButton())
                    .disabled(!canSubmit)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    Button("Don't have an account? Create one") {
                        showRegister = true
                    }
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                    .padding(.top, 16)

                    Spacer()
                }
            }
            .onTapGesture {
                focusedField = nil
            }
            .peScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showRegister) {
                RegisterView(viewModel: viewModel)
            }
        }
    }
}

#Preview {
    LoginView(viewModel: AuthViewModel(
        authRepository: MockAuthRepository(),
        tokenStore: TokenStore()
    ))
}
