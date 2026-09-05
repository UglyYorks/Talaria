# Local credential helper

Self-signed macOS Keychain clients are partitioned by code hash. Talaria's
development builds therefore use a separately installed, stable helper.

Run `make install-credential-helper` once with the same `CODE_SIGN_IDENTITY` as
the app. This installs a hardened helper under the user's Application Support
folder and an on-demand LaunchAgent. It does not modify or copy credentials.
Approve **Talaria Credentials** in the native Keychain dialog with **Always
Allow** when Talaria first accesses the existing credential.

Normal `make build`, `make run`, and `make clean` do not alter the installed
helper. The installer is idempotent and refuses to overwrite a different
installed helper. Updating the helper or changing its signing certificate needs
an explicit upgrade and another Keychain approval; do not repeatedly reinstall
it as part of ordinary app development.

The XPC peers require both the expected bundle identifier and the same leaf
signing certificate. The helper exposes only read/write/delete for the existing
`com.talaria.chat.credentials` / `openRouterToken` item, plus a credential-free
ping. The client fails closed if the trusted helper is unavailable. No token is
passed via command-line arguments, files, or logs. Custom-service credential
stores retain their direct Keychain implementation for isolated tests.

`make test-credential-helper` runs signed ping probes (authorized, unauthorized,
authorized again) against the installed service without reading credentials.
The ordinary test suite remains independent of an installed helper.

To stop using the helper, first switch the app back to direct Keychain access
with Apple-issued signing. Then unload the exact user LaunchAgent using
`launchctl bootout gui/$(id -u)/com.talaria.chat.credentials-helper` and remove
its plist and the dedicated `Talaria/CredentialHelper` installation folder.
Leave the existing Keychain item intact.
