# Testing Guide: App Authorization and Scope System

This guide walks through testing the new app authorization system with scope validation.

## Prerequisites

1. Start the Phoenix server:
   ```bash
   cd /home/pof/code/balados/balados.sync
   mix phx.server
   ```

2. Ensure you have a user account created. If not, register at `http://localhost:4000/users/register`

## Test 1: Token Generator Page

**Objective**: Verify the app creator interface works correctly

1. Visit `http://localhost:4000/app-creator`
2. Verify the form has these fields:
   - App ID (text input)
   - App Name (text input)
   - App URL (text input)
   - App Image URL (text input)
   - Scope checkboxes (organized by category)
   - Key generation buttons
   - Private/Public key text areas

3. Click "Generate Keys" and verify RSA key pair is generated
4. Fill in the form:
   - **App ID**: `com.test.podcast-app`
   - **App Name**: `Test Podcast App`
   - **App URL**: `https://test.example.com`
   - **App Image**: `https://test.example.com/icon.png`
   - Select scopes: `user.subscriptions.read`, `user.plays.write`

5. Click "Generate Token"
6. Verify:
   - A JWT token appears in the result section
   - The authorization URL is displayed
   - Copy the authorization token for next test

## Test 2: Authorization Flow

**Objective**: Verify users can authorize apps

1. Using the authorization URL from Test 1, visit the authorization page
2. If not logged in, you should be redirected to login
3. After login, verify the authorization page shows:
   - App name: "Test Podcast App"
   - App URL (clickable link)
   - Selected scopes with human-readable labels:
     - "List podcast subscriptions"
     - "Update playback positions and mark episodes as played"
   - User count display (should show "~0 users" or similar for first use)
   - App image should NOT be visible (< 10% threshold)

4. Click "Authorize Application"
5. Verify redirect to dashboard with success message
6. Note: Store the app_id and private key for API testing

## Test 3: Re-authorization with Different Scopes

**Objective**: Verify apps can update their scope permissions

1. Go back to `/app-creator`
2. Use the SAME app_id: `com.test.podcast-app`
3. Generate NEW keys (or reuse old keys)
4. Select DIFFERENT scopes: `user.subscriptions.read`, `user.subscriptions.write`, `user.plays.read`
5. Generate new authorization token
6. Authorize again
7. Verify:
   - No error about duplicate authorization
   - Scopes are updated (should now have 3 scopes)

## Test 4: Manage Authorized Apps Page

**Objective**: Verify users can view and manage authorized apps

1. Visit `http://localhost:4000/apps`
2. Verify the page shows:
   - List of authorized apps
   - "Test Podcast App" should appear
   - App details (name, URL, scopes with labels)
   - User count display
   - "Revoke Access" button

3. Note the app_id displayed
4. Don't revoke yet (needed for API tests)

## Test 5: API Request with Valid Scopes

**Objective**: Verify API requests work with proper scopes

### 5.1 List Subscriptions (Read Scope)

1. Create an API request JWT using your private key and app_id:
   ```elixir
   # In iex -S mix:
   alias BaladosSyncWeb.AppAuth

   # Your values from Test 1
   app_id = "com.test.podcast-app"
   user_id = "your_user_id"  # Get from database or session
   private_key = """
   -----BEGIN PRIVATE KEY-----
   ...your private key...
   -----END PRIVATE KEY-----
   """

   # Create JWT
   claims = %{
     "iss" => app_id,
     "sub" => user_id,
     "iat" => :os.system_time(:second),
     "exp" => :os.system_time(:second) + 3600
   }

   signer = Joken.Signer.create("RS256", %{"pem" => private_key})
   {:ok, token, _} = Joken.encode_and_sign(claims, signer)
   IO.puts("Bearer #{token}")
   ```

2. Make API request:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
        http://localhost:4000/api/v1/subscriptions
   ```

3. Expected: 200 OK with subscriptions list (or empty array)

### 5.2 Create Subscription (Write Scope)

1. Using the same token from 5.1
2. Make POST request:
   ```bash
   curl -X POST \
        -H "Authorization: Bearer YOUR_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk"}' \
        http://localhost:4000/api/v1/subscriptions
   ```

3. Expected: 201 Created (if you authorized write scope in Test 3)
4. If you only have read scope: 403 Forbidden with "Insufficient permissions"

### 5.3 Update Play Position (Write Scope)

1. Make PUT request:
   ```bash
   curl -X PUT \
        -H "Authorization: Bearer YOUR_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"position": 120}' \
        http://localhost:4000/api/v1/plays/ITEM_ID/position
   ```

2. Expected: 200 OK (you have user.plays.write)

## Test 6: API Request with Insufficient Scopes

**Objective**: Verify scope validation blocks unauthorized requests

1. Create a NEW app authorization with ONLY read scopes:
   - App ID: `com.test.readonly-app`
   - Scopes: ONLY `user.subscriptions.read`

2. Authorize this app
3. Create JWT token for this app
4. Try to CREATE a subscription:
   ```bash
   curl -X POST \
        -H "Authorization: Bearer READONLY_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk"}' \
        http://localhost:4000/api/v1/subscriptions
   ```

5. Expected: 403 Forbidden with `{"error": "Insufficient permissions"}`

## Test 7: Wildcard Scope Matching

**Objective**: Verify wildcard scopes grant appropriate permissions

### 7.1 Test `user.*` Wildcard

1. Create app with scope: `user.*`
2. Authorize it
3. Test all endpoints:
   - GET /api/v1/subscriptions ✓ (should work)
   - POST /api/v1/subscriptions ✓ (should work)
   - GET /api/v1/plays ✓ (should work)
   - POST /api/v1/plays ✓ (should work)
   - GET /api/v1/privacy ✓ (should work)
   - PUT /api/v1/privacy ✓ (should work)

### 7.2 Test `*.read` Wildcard

1. Create app with scope: `*.read`
2. Authorize it
3. Test endpoints:
   - GET /api/v1/subscriptions ✓ (should work)
   - POST /api/v1/subscriptions ✗ (should fail 403)
   - GET /api/v1/plays ✓ (should work)
   - POST /api/v1/plays ✗ (should fail 403)

### 7.3 Test `*` Full Access

1. Create app with scope: `*`
2. Authorize it
3. All endpoints should work

## Test 8: Image Visibility Threshold

**Objective**: Verify image display logic based on adoption percentage

### Setup: Need at least 10 users for this test

1. Create 10 test users (or use existing users if available)
2. Have 1 user authorize an app with an image
3. Visit `/authorize` for that app
4. Expected: Image should NOT be visible (<10%)
5. User display should show "~10 users" or "~0 users"

6. Have 2-3 more users authorize the same app
7. Visit `/authorize` again
8. Expected: Still no image if < 10% of total users

9. Once ≥10% of users authorize:
10. Expected: Image becomes visible
11. User display shows "X% of users" (rounded up)

### Alternative Test (with 1 user)

1. Check the image visibility code in manage_apps page
2. Verify the logic: `show_image = percentage >= 10.0`
3. Verify user display logic:
   - `percentage < 1.0`: Shows "~X0 users" (rounded to 10)
   - `percentage >= 1.0`: Shows "X% of users" (rounded up)

## Test 9: Revoke App Authorization

**Objective**: Verify users can revoke app access

### 9.1 Via Web Interface

1. Go to `http://localhost:4000/apps`
2. Find your test app
3. Click "Revoke Access"
4. Verify:
   - App is removed from list or marked as revoked
   - Success message appears

5. Try to make API request with previously valid token
6. Expected: 401 Unauthorized (app authorization revoked)

### 9.2 Via API

1. Create and authorize a new app
2. Get an API token for this app
3. Make DELETE request:
   ```bash
   curl -X DELETE \
        -H "Authorization: Bearer YOUR_TOKEN" \
        http://localhost:4000/api/v1/apps/com.test.podcast-app
   ```

4. Expected: 200 OK with `{"status": "success", "message": "App authorization revoked"}`

5. Try to use the token again
6. Expected: 401 Unauthorized

## Test 10: Invalid Token Scenarios

**Objective**: Verify proper error handling

### 10.1 Expired Token

1. Create JWT with exp in the past
2. Make API request
3. Expected: 401 Unauthorized

### 10.2 Invalid Signature

1. Create JWT with wrong private key
2. Make API request
3. Expected: 401 Unauthorized

### 10.3 Missing Claims

1. Create JWT without `iss` field
2. Expected: Authorization should fail at `/authorize` step

### 10.4 Unauthorized App

1. Create valid JWT for app_id that was never authorized
2. Make API request
3. Expected: 401 Unauthorized

## Test 11: List Authorized Apps API

**Objective**: Verify API endpoint for listing apps

1. Authorize 2-3 different apps
2. Make GET request:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
        http://localhost:4000/api/v1/apps
   ```

3. Expected: 200 OK with JSON:
   ```json
   {
     "apps": [
       {
         "id": "uuid",
         "app_id": "com.test.podcast-app",
         "app_name": "Test Podcast App",
         "app_url": "https://test.example.com",
         "app_image": "https://test.example.com/icon.png",
         "scopes": ["user.subscriptions.read", "user.plays.write"],
         "last_used_at": "2025-11-24T...",
         "inserted_at": "2025-11-24T...",
         "updated_at": "2025-11-24T..."
       }
     ]
   }
   ```

## Success Criteria

All tests should pass with:
- ✅ Authorization flow works correctly
- ✅ Scope validation blocks unauthorized requests
- ✅ Wildcard scopes work as expected
- ✅ App management interface functional
- ✅ API endpoints respect scope requirements
- ✅ Revocation works via web and API
- ✅ Error handling is appropriate
- ✅ Image visibility logic works correctly

## Troubleshooting

### Common Issues

**"Invalid authorization token"**
- Check JWT structure: must have `iss`, `app`, `scopes`
- Verify JWT signature with public key
- Check expiration time

**"Insufficient permissions" (403)**
- Check granted scopes in database
- Verify endpoint scope requirements
- Test wildcard matching

**"Invalid or revoked token" (401)**
- Check if app authorization exists and is not revoked
- Verify JWT signature matches authorized public key
- Check API request JWT has correct `iss` and `sub`

**Image not showing**
- Check if ≥10% of users authorized the app
- Verify `app_image` field is set
- Check browser console for image loading errors

## Clean Up

After testing, revoke all test app authorizations:

```bash
# Via API
curl -X DELETE -H "Authorization: Bearer TOKEN" \
     http://localhost:4000/api/v1/apps/com.test.podcast-app

curl -X DELETE -H "Authorization: Bearer TOKEN" \
     http://localhost:4000/api/v1/apps/com.test.readonly-app
```

Or use the web interface at `http://localhost:4000/apps`
