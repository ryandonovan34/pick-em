import Foundation

@Observable
@MainActor
final class GroupViewModel {
    var groups: [Group] = []
    var isLoading = true
    var errorMessage: String?

    private let groupRepository: any GroupRepositoryProtocol

    init(groupRepository: any GroupRepositoryProtocol) {
        self.groupRepository = groupRepository
    }

    func loadGroups() async {
        isLoading = true
        groups = []
        errorMessage = nil
        defer { isLoading = false }
        do {
            groups = try await groupRepository.fetchGroups()
        } catch {
            errorMessage = "Failed to retrieve groups: \(error.localizedDescription)"
        }
    }

    func createGroup(
        name: String,
        sport: Sport,
        mode: ChallengeMode,
        seasonYear: Int?,
        blindPicks: Bool,
        superdogsEnabled: Bool,
        superdogsPerUser: Int,
        includePreseason: Bool,
        includePlayoffs: Bool
    ) async -> Group? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let group = try await groupRepository.createGroup(
                name: name, sport: sport, mode: mode,
                seasonYear: seasonYear, blindPicks: blindPicks,
                superdogsEnabled: superdogsEnabled, superdogsPerUser: superdogsPerUser,
                includePreseason: includePreseason, includePlayoffs: includePlayoffs
            )
            groups.append(group)
            return group
        } catch {
            errorMessage = "Failed to create group: \(error.localizedDescription)"
            return nil
        }
    }

    func joinGroup(joinCode: String) async -> Group? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let group = try await groupRepository.joinGroup(joinCode: joinCode)
            if !groups.contains(where: { $0.id == group.id }) {
                groups.append(group)
            }
            return group
        } catch {
            errorMessage = "Failed to join group: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func deleteGroup(groupID: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await groupRepository.deleteGroup(groupID: groupID)
            groups.removeAll { $0.id == groupID }
            return true
        } catch {
            errorMessage = "Failed to delete group: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func leaveGroup(groupID: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await groupRepository.leaveGroup(groupID: groupID)
            groups.removeAll { $0.id == groupID }
            return true
        } catch {
            errorMessage = "Failed to leave group: \(error.localizedDescription)"
            return false
        }
    }
}
