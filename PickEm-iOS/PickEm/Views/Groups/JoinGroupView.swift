import SwiftUI

struct JoinGroupView: View {
    var viewModel: GroupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var joinCode = ""

    var body: some View {
        Form {
            Section {
                TextField(
                    "",
                    text: $joinCode,
                    prompt: Text("e.g. CREW23").foregroundStyle(AdaptiveColor.peOutline)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(AdaptiveColor.peOnSurface)
                .autocapitalization(.allCharacters)
                .font(.peHeadlineMd())
                .tracking(4)
                .onChange(of: joinCode) { _, newValue in
                    joinCode = String(newValue.prefix(6).uppercased())
                }
            } header: {
                Text("ENTER THE 6-CHARACTER CODE SHARED BY YOUR GROUP ADMIN.")
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
            .listRowBackground(AdaptiveColor.peSurfaceLow)

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peError)
                }
                .listRowBackground(AdaptiveColor.peSurfaceLow)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveColor.peBackground)
        .navigationTitle("Join Group")
        .navigationBarTitleDisplayMode(.inline)
        .peNavBar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(AdaptiveColor.pePrimary)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Join") {
                    Task {
                        let group = await viewModel.joinGroup(joinCode: joinCode)
                        if group != nil { dismiss() }
                    }
                }
                .font(.peLabelBold())
                .foregroundStyle(joinCode.count < 6 || viewModel.isLoading ? AdaptiveColor.peOutline : AdaptiveColor.pePrimaryFill)
                .disabled(joinCode.count < 6 || viewModel.isLoading)
            }
        }
    }
}

#Preview {
    NavigationStack {
        JoinGroupView(viewModel: GroupViewModel(groupRepository: MockGroupRepository()))
    }
}
