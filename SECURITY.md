# Security

## Reporting

Report a vulnerability privately through
[GitHub's advisory form](https://github.com/merksam/tyto/security/advisories/new).
That reaches me directly and stays private until there is a fix. Please do not open a
public issue for a security problem.

I am one person and this is a side project, so I cannot promise a response time. I will
acknowledge a report when I see it and tell you what I intend to do.

## What the attack surface actually is

Worth stating plainly, because it is small and that shapes what is worth reporting.

Tyto contains no networking code, has no accounts, no server and no IPC with anything
outside itself. It is sandboxed with four entitlements: the sandbox, read/write to
Pictures, user-selected files for the save panel, and app-scoped bookmarks. There is no
`com.apple.security.network.client`, so the sandbox blocks outbound connections whether or
not any code attempted one.

The parts where a real bug could live:

- **Saved file paths.** Tyto writes PNGs into your save folder and reads them back to list
  recent captures. A path handling bug is the most plausible place something goes wrong.
- **Security-scoped bookmarks.** A chosen save folder is stored as a bookmark and resolved
  on later launches.
- **Screen Recording permission.** Tyto takes a single still when you press the shortcut.
  Anything that caused it to capture at another moment would be a serious bug and I want
  to hear about it.
- **Debug builds only.** Debug builds open a unix socket inside the app container for the
  test harness. It is compiled out of Release entirely, so the App Store build does not
  have it. If you find it in a release build, that is a bug worth reporting.

## Scope

In scope: the app in this repository, and the site in `site/`.

Not in scope: anything that requires an attacker to already have code execution or your
login on your Mac, and the third-party services the website loads (Cloudflare, Google
Fonts, Ko-fi) — report those to them.
