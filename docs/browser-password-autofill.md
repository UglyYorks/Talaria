# System password AutoFill

Focus a website's username or password field and choose **Edit → AutoFill Password…**
(`⌘\`), or right-click the field and choose **AutoFill Password…**.

In the native dialog, click the Password field and choose **Passwords…**. If the
suggestion does not appear, right-click that native field and choose
**AutoFill → Passwords…**. Select the saved login for the website shown in the
dialog, complete any macOS authentication, and click **Fill**. Talaria fills the
form without submitting it. Username-first and password-only sign-in pages are
supported, including in private windows.

This uses AppKit's system AutoFill support for native username and secure password
fields. It opens the macOS chooser; it does not add Safari's inline website
suggestions or automatic password saving. macOS controls the available password
providers and authentication. Talaria does not import or maintain a password
vault, access the clipboard, or send credentials to the assistant.

The command requires HTTPS for both the top-level page and requesting frame.
Opaque frames, non-HTTPS destinations, forms whose action points to another origin,
new-password fields, and ambiguous multiple-password forms are excluded. The isolated-world
bridge binds a fill to the original document, form, and inputs. Navigation,
replacement, or changes to the form's destination invalidate it. The native fields
are cleared when the dialog closes, and each selection is delivered at most once.

HTTP authentication dialogs also annotate their native username/password fields
for system AutoFill.

Run `make test-browser-password-autofill` for a signed desktop test from the current
worktree. It uses simulated WebKit responses and synthetic credentials, covering
both persistent and nonpersistent sessions. It does not select real saved logins.

Apple describes the native field integration in
[AutoFill everywhere](https://developer.apple.com/videos/play/wwdc2020/10115/).
