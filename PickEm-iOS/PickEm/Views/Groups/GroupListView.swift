import SwiftUI

struct GroupListView: View {
    var viewModel: GroupViewModel
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCreate = false
    @State private var showJoin = false

    private var separatorColor: Color {
        colorScheme == .dark ? Color(hex: "3c494e") : Color(hex: "bac9cc")
    }

    var body: some View {
        List {
            if viewModel.groups.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Groups Yet",
                    systemImage: "person.3",
                    description: Text("Create a group or join one with a code.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.groups) { group in
                    NavigationLink(value: group) {
                        GroupRow(group: group)
                    }
                    .listRowBackground(AdaptiveColor.peSurfaceLow)
                    .listRowSeparatorTint(separatorColor)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveColor.peBackground)
        .navigationDestination(for: Group.self) { group in
            GroupDetailView(group: group, groupViewModel: viewModel, dependencies: dependencies)
        }
        .navigationTitle("My Groups")
        .peNavBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Create Group") { showCreate = true }
                    Button("Join Group") { showJoin = true }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AdaptiveColor.pePrimary)
                }
            }
        }
        .refreshable { await viewModel.loadGroups() }
        .onLoad { await viewModel.loadGroups() }
        .overlay {
            if viewModel.isLoading && viewModel.groups.isEmpty {
                LoadingView()
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreateGroupView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showJoin) {
            NavigationStack {
                JoinGroupView(viewModel: viewModel)
            }
        }
    }
}

private struct GroupRow: View {
    let group: Group

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name.uppercased())
                .font(.peHeadlineMd())
                .foregroundStyle(AdaptiveColor.peOnSurface)
            HStack(spacing: 12) {
                Label(group.sport.displayName, systemImage: "sportscourt")
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                Label(group.mode.displayName, systemImage: "calendar")
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        GroupListView(viewModel: GroupViewModel(groupRepository: MockGroupRepository()))
            .environment(AppDependencies())
    }
}
