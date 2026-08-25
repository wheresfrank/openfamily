# Contributing

Issues and pull requests are welcome.

Open pull requests against `main`. Do not stack a PR on another feature branch.
The `backend` and `flutter` checks must pass before merge.

Please:

1. Keep location data on the user's server — no analytics, crash reporters,
   or third-party SDKs that exfiltrate coordinates.
2. Match the existing Go / Flutter / TypeScript style in the tree you touch.
3. Do not commit secrets, `.env`, or APNs keys.

Report security issues privately — see [SECURITY.md](SECURITY.md).
