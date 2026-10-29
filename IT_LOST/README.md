# CampusFind

CampusFind is a Flutter lost-and-found app with email/password registration, email verification, and login. The Node.js API stores accounts, verification codes, profile details, and sessions in a local JSON file. Passwords are stored as scrypt hashes, emails are normalized, and duplicate addresses are rejected. Session tokens are stored as hashes.

## Start the API

Requirements: Node.js 20+ and Flutter.

1. Copy `backend/.env.example` to `backend/.env` and set `JSON_DB_FILE` if you want the data file somewhere other than `backend/data/users.json`. Configure optional SMTP settings if you wish to send real emails; in development mode without SMTP, verification codes are logged directly to the server console.
2. Run `npm install` and `npm run migrate` from `backend` to initialize the JSON file.
3. Start the API with `npm run dev` from `backend`. It listens on port 3000.

The API routes are:
- `POST /auth/register`: Initiates registration with full name, unique email, password, and confirm password. Creates an unverified account and generates a 6-digit verification code.
- `POST /auth/verify-email`: Verifies the 6-digit code, activates the account, and returns an authenticated session.
- `POST /auth/resend-verification`: Resends a 6-digit verification code.
- `POST /auth/login`: Authenticates verified accounts.
- `GET /auth/me`: Fetches the current authenticated user.
- `PUT /auth/profile`: Updates profile contact and social links.
- `POST /auth/logout`: Revokes active sessions.

Duplicate email registrations return HTTP 409. JSON writes are serialized and use atomic file replacement. Run one API process only; a local JSON file is not appropriate for multiple server instances or high-concurrency production use.

## Run Flutter

Start the API first. The default API URL is `http://10.0.2.2:3000` for Android emulators and localhost for desktop/web. For a physical phone, pass the development computer's LAN URL:

```powershell
flutter run --dart-define=AUTH_API_URL=http://192.168.1.10:3000
```

Use HTTPS and set `CORS_ORIGINS` for production/web deployments. The mobile app stores the session token in secure storage; profile and account records remain in the API's JSON file.

## Tests

Run backend tests with `cd backend && npm test`. Run Flutter tests and analysis from this directory with `flutter test` and `flutter analyze`. Tests use temporary JSON files and do not require a database service.
