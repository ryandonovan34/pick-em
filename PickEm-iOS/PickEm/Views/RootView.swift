import SwiftUI

struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        AuthGate(authViewModel: dependencies.authViewModel)
    }
}

/// Observes AuthViewModel directly so SwiftUI re-renders when isAuthenticated flips.
private struct AuthGate: View {
    var authViewModel: AuthViewModel
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        if authViewModel.isAuthenticated {
            mainContent
        } else {
            LoginView(viewModel: authViewModel)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            GroupListView(
                viewModel: GroupViewModel(groupRepository: dependencies.groupRepository)
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        Task { await authViewModel.logout() }
                    }
                }
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppDependencies())
}
