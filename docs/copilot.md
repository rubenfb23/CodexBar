---
summary: "Copilot provider data sources: GitHub device flow + Copilot internal usage API."
read_when:
  - Debugging Copilot login or usage parsing
  - Updating GitHub OAuth device flow behavior
---

# Copilot provider

Copilot uses GitHub OAuth device flow and the Copilot internal usage API. No browser cookies.

## Data sources + fallback order

1) **GitHub OAuth device flow** (user initiated)
   - Device code request:
     - `POST https://github.com/login/device/code`
   - Token polling:
     - `POST https://github.com/login/oauth/access_token`
   - Scope: `read:user`.
   - Token stored in config:
     - `~/.codexbar/config.json` → `providers[].apiKey` for `copilot`

2) **Usage fetch**
   - `GET https://api.github.com/copilot_internal/user`
   - Headers:
     - `Authorization: token <github_oauth_token>`
     - `Accept: application/json`
     - `Editor-Version: vscode/1.96.2`
     - `Editor-Plugin-Version: copilot-chat/0.26.7`
     - `User-Agent: GitHubCopilotChat/0.26.7`
     - `X-Github-Api-Version: 2025-04-01`

## Snapshot mapping
- Primary: `quotaSnapshots.premiumInteractions` percent remaining → used percent.
- Secondary: `quotaSnapshots.chat` percent remaining → used percent.
- Reset dates are not provided by the API.
- Plan label from `copilotPlan`.

## Linux token setup

On macOS the token is stored in Keychain. On Linux it lives in `~/.codexbar/config.json`.

To configure via the UI: **Preferences → Providers → Copilot → API Token field → Save**.

To get the token:
```bash
gh auth token   # GitHub CLI — already signed in
```
Or create a PAT at GitHub → Settings → Developer settings → Personal access tokens with `copilot` scope.

## Key files
- `Sources/CodexBarCore/Providers/Copilot/CopilotUsageFetcher.swift`
- `Sources/CodexBarCore/Providers/Copilot/CopilotDeviceFlow.swift`
- `Sources/CodexBar/Providers/Copilot/CopilotLoginFlow.swift`
- `Sources/CodexBar/CopilotTokenStore.swift` (legacy migration helper)
