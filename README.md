# Final_Campus-Find

CampusFind is a Flutter lost-and-found app with email/password registration,
email verification, and login. The Flutter project lives at the repository
root, with its Node.js API in the sibling `backend` folder.

## Start the API

Requirements: Node.js 20+ and Flutter.

Run the API from the repository root:

```powershell
Set-Location .\backend
npm install
npm run dev
```

The first `npm run dev` creates `backend/.env` with a random local development
secret. Verification codes are logged to the server console when SMTP is not
configured. The API listens on port 3000.

## Run Flutter

The default API URL is `http://10.0.2.2:3000` for Android emulators and
localhost for desktop/web. For a physical phone, pass the development
computer's LAN URL:

```powershell
flutter run --dart-define=AUTH_API_URL=http://192.168.1.10:3000
```

Run the web app locally with:

```powershell
flutter pub get
flutter run -d edge
```

In VS Code, select `CampusFind (Web)` to start Edge; the API starts first. In
Android Studio, open the repository root as the Flutter project and select an
emulator or connected device.

Use HTTPS and set `CORS_ORIGINS` for production/web deployments.

## Tests

Run Flutter analysis and tests from the repository root:

```powershell
flutter analyze
flutter test
```

Run backend tests from `backend`:

```powershell
Set-Location .\backend
npm test
```
