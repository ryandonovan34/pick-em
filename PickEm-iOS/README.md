# PickEm iOS

Sports pick'em challenge app. Pick games against the spread, compete on a season-long leaderboard with your group.

---

## Prerequisites

- **Xcode 16+**
- **iOS deployment target**: 17.0
- **Required capabilities** (add in Xcode → Signing & Capabilities when connecting to a real backend):
  - Push Notifications
  - Background Fetch

---

## Scheme Configuration

Three schemes control which data backend the app uses. Switch via `Product → Scheme` in Xcode.

| Scheme | Flag | Data source |
|--------|------|-------------|
| `MockLocal` | `MOCK_LOCAL` | Hardcoded in-memory mock data — no network (Phase 1) |
| `MockBackend` | `MOCK_BACKEND` | Local FastAPI dev server (Phase 2) |
| `Live` | *(none)* | Production API (Phase 4) |

The active flag is set per-scheme via `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in the Xcode project. `AppDependencies.swift` uses `#if MOCK_LOCAL / #elseif MOCK_BACKEND / #else` to swap all repository implementations at once — ViewModels and Views never know which is active.

---

## Running Against Local Mock Data (Phase 1)

1. Select the **MockLocal** scheme in Xcode.
2. Build and run on any simulator or device — no configuration needed.
3. All data comes from `MockData.swift` in-memory. Login with any credentials (the mock auth repository accepts anything).

---

## Running Against the Local Backend (Phase 2)

1. Start the FastAPI dev server (`APP_ENV=development uvicorn app.main:app --reload`).
2. Select the **MockBackend** scheme in Xcode.
3. In `Product → Scheme → Edit Scheme → Run → Environment Variables`, set `DEV_SERVER_URL` to `http://localhost:8000` (already pre-filled as the default).
4. Build and run.

---

## Running Against Production (Phase 4)

1. Select the **Live** scheme.
2. Set `API_BASE_URL` in the scheme's environment variables to your Fly.io app URL.
3. Add `GoogleService-Info.plist` to the project root (see APNs / FCM Setup below).

---

## APNs / FCM Setup

> Required only for Phase 4 (production push notifications).

1. Register the App ID for Push Notifications in the [Apple Developer portal](https://developer.apple.com).
2. Download the APNs Auth Key (`.p8`) from the portal.
3. Create a Firebase project (FCM only — no other Firebase services needed).
4. Upload the APNs key to Firebase → Project Settings → Cloud Messaging.
5. Download `GoogleService-Info.plist` and drag it into the Xcode project root.
6. Add the **Push Notifications** and **Background Modes → Remote notifications** capabilities in Xcode → Signing & Capabilities.

---

## Running Tests

All tests use `LocalMockRepository` — no network or backend required.

```bash
xcodebuild test \
  -project PickEm.xcodeproj \
  -scheme MockLocal \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or run via `Cmd+U` in Xcode with the `MockLocal` scheme selected.

**Test coverage includes:**
- `DomainModelTests/` — spread rounding, superdog eligibility, lock state, win % calculation
- `ViewModelTests/` — auth, group, slate, pick, standings ViewModels against mock repositories
- `RepositoryTests/` — mock repository contract tests (conflict, not found, CRUD)
- `DTOMappingTests/` — DTO → domain model mapping

---

## Project Structure

```
PickEm/
├── App/                        # Entry point + DI root
│   ├── PickEmApp.swift
│   ├── AppDependencies.swift   # Swap repo implementations here
│   └── TokenStore.swift
├── Domain/
│   ├── Models/                 # User, Group, Game, Pick, Week, Standing
│   └── Enums/                  # Sport, ChallengeMode, PickResult
├── DTOs/                       # API response shapes + toDomain() mappers
├── Repositories/
│   ├── Protocols/              # One protocol per resource
│   ├── Live/                   # NetworkService-backed implementations
│   └── Mock/                   # In-memory mock implementations + MockData
├── Services/
│   ├── NetworkService.swift    # Base HTTPS client, auth header injection
│   ├── LocalCacheService.swift # SwiftData cache + invalidate(scope:)
│   └── NotificationService.swift  # APNs token + silent FCM push handling
├── ViewModels/                 # @MainActor ObservableObjects
└── Views/
    ├── Auth/                   # LoginView, RegisterView
    ├── Groups/                 # GroupListView, CreateGroupView, JoinGroupView, GroupDetailView
    ├── Slate/                  # SlateView, GameRowView, PickSubmissionView
    ├── Standings/              # LeaderboardView
    ├── Common/                 # LoadingView, ErrorView
    └── RootView.swift          # Auth gate → main navigation
```

---

## Build Phases

| Phase | Status | Description |
|-------|--------|-------------|
| **Phase 1** | ✅ Complete | Full iOS app against `LocalMockRepository` |
| **Phase 2** | Pending | Backend + `MockBackendRepository` |
| **Phase 3** | Pending | Live Odds API integration |
| **Phase 4** | Pending | Production deployment + FCM |
