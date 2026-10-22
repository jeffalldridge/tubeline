# Security Policy

Tubeline runs locally, makes no network requests, and is sandboxed (it can only read files
you drop or choose, and write where you allow). It parses untrusted SVG/XML files, so parser
crashes and hangs count as security bugs.

## Reporting a vulnerability

Please **don't** open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/jeffalldridge/tubeline/security/advisories/new)
and include the file or steps that reproduce it. Expect a reply within a week.

Only the latest release is supported.
