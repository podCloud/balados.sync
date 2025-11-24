# Recent Changes Summary

This document summarizes the major refactoring of the app authorization system.

## Completed Changes

### 1. Database Schema Changes
- ✅ Renamed `api_tokens` table to `app_tokens`
- ✅ Renamed `user_tokens` table to `play_tokens`
- ✅ Replaced `token_jti` field with `app_id` field
- ✅ Added unique index on `(user_id, app_id)` combination
- ✅ Added index on `(app_id, public_key)` for app popularity tracking

### 2. Schema Modules
- ✅ Created `AppToken` schema (replaced `ApiToken`)
- ✅ Created `PlayToken` schema (replaced `UserToken`)
- ✅ Added scope validation in AppToken changeset
- ✅ Updated all field names and constraints

### 3. Comprehensive Scope System
- ✅ Created `BaladosSyncWeb.Scopes` module with:
  - Complete scope hierarchy (user, user.subscriptions, user.plays, user.playlists, user.privacy, user.sync)
  - Wildcard support (`*`, `*.read`, `user.*`, `user.*.read`)
  - Scope matching and authorization functions
  - Human-readable scope descriptions
- ✅ Implemented wildcard pattern matching
- ✅ Added `authorized?/2`, `authorized_all?/2`, `authorized_any?/2` functions

### 4. JWT Authentication System
- ✅ Updated `AppAuth` module to:
  - Use `app_id` from JWT `iss` field (instead of `jti`)
  - Look up apps by `(user_id, app_id)` combination
  - Validate scopes using the Scopes module
  - Update existing authorizations when scopes change
  - Calculate app usage statistics for image visibility
- ✅ Updated `JWTAuth` plug to:
  - Use new AppAuth.verify_app_request/1 function
  - Check scopes with `scopes: [...]` and `scopes_any: [...]` options
  - Return 403 Forbidden for insufficient permissions
  - Assign app_id, app_token, and jwt_claims to conn

### 5. Controller Updates
- ✅ Updated `AppAuthController` to:
  - Use app_id instead of jti
  - Calculate image visibility based on 10% threshold
  - Show user count/percentage on authorization page
  - Add `manage_apps/2` action for HTML app management page
  - Include scope labels with human-readable descriptions
- ✅ Updated API endpoints: `DELETE /api/v1/apps/:app_id` (was `:jti`)

### 6. UI Improvements
- ✅ Updated authorization page (`authorize.html.heex`) with:
  - Image visibility based on 10% user threshold
  - User count display (rounded to nearest 10 if <1%, percentage if ≥1%)
  - Human-readable scope labels
  - Visual scope hierarchy display
- ✅ Created manage apps page (`manage_apps.html.heex`) with:
  - List of authorized apps
  - Image visibility logic
  - Scope badges
  - Revoke access buttons
  - Last used timestamps

### 7. Router Updates
- ✅ Added `GET /apps` route for manage_apps HTML page
- ✅ Updated `DELETE /api/v1/apps/:app_id` route

### 8. Migrations
- ✅ Migration to rename api_tokens → app_tokens
- ✅ Migration to rename token_jti → app_id
- ✅ Migration to rename user_tokens → play_tokens
- ✅ All migrations have been run successfully

## Remaining Work

### 1. Token Generator Page (High Priority)
**File**: `apps/balados_sync_web/lib/balados_sync_web/controllers/page_html/app_creator.html.heex`

**Changes needed**:
- Replace text input for scopes with checkbox list of all available scopes
- Add app_id field for the JWT iss claim
- Remove jti generation from JavaScript
- Update JWT payload to include iss field
- Update scope selection to use checkbox interface

### 2. Controller Scope Requirements (Medium Priority)
**Files**: Various controllers in `apps/balados_sync_web/lib/balados_sync_web/controllers/`

**Changes needed**:
- Add scope requirements to controller actions
- Example for SubscriptionController:
  ```elixir
  plug JWTAuth, [scopes: ["user.subscriptions.read"]] when action in [:index]
  plug JWTAuth, [scopes: ["user.subscriptions.write"]] when action in [:create, :delete]
  ```
- Apply to:
  - SubscriptionController (user.subscriptions.*)
  - PlayController (user.plays.*)
  - PrivacyController (user.privacy.*)
  - EpisodeController (user.plays.write for save/share)

### 3. Documentation Updates (Medium Priority)
**Files**:
- `CLAUDE.md`
- `docs/api/*.livemd`

**Changes needed**:
- Update CLAUDE.md with new authentication flow
- Document app_id vs jti change
- Document scope system
- Update API documentation examples
- Add scope requirements to endpoint documentation

### 4. Clean Up Old Schema References (Low Priority)
**Changes needed**:
- Remove old `api_token.ex` file
- Remove old `user_token.ex` file
- Search codebase for any remaining references to ApiToken or UserToken

### 5. Testing (High Priority)
**Changes needed**:
- Test authorization flow with new app_id system
- Test scope validation in JWT auth plug
- Test image visibility logic
- Test manage_apps page
- Update any existing tests that reference jti or ApiToken

## Breaking Changes

### For Third-Party App Developers

1. **JWT Structure Change**:
   - MUST include `iss` field with app_id (instead of `jti`)
   - MUST nest app details under `app` key
   - MUST request specific scopes (or `*` for full access)

2. **API Endpoints**:
   - App deletion now uses `DELETE /api/v1/apps/:app_id` (not `:jti`)

3. **Scope Requirements**:
   - Apps must request appropriate scopes
   - Wildcards supported: `*`, `*.read`, `user.*`, `user.*.read`

### Migration Guide for Existing Apps

If you have existing apps that need to be migrated:

1. Update JWT generation to include `iss` field with your app_id
2. Remove `jti` field from JWT
3. Request appropriate scopes in JWT
4. Update any API calls that referenced jti to use app_id

## Testing Checklist

- [ ] Create authorization JWT with new structure
- [ ] Test authorization flow in browser
- [ ] Verify image visibility threshold (10%)
- [ ] Test scope validation in API requests
- [ ] Verify manage_apps page displays correctly
- [ ] Test app revocation
- [ ] Test token generator page (after updates)
- [ ] Run existing test suite

## Notes

- The scope system uses hierarchical permissions (e.g., `user` grants `user.read` and `user.write`)
- Image visibility requires ≥10% of users to have authorized the app
- User count shown as "~X0 users" if <1%, "X%" if ≥1%
- App uniqueness determined by (app_id, public_key) pair across all users
