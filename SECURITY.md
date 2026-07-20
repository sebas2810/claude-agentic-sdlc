# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Report it privately via GitHub's private vulnerability reporting instead:
<https://github.com/sebas2810/claude-agentic-sdlc/security/advisories/new>

Include enough detail to reproduce the issue: the affected file or script,
steps to reproduce, and the impact you see. You can expect an acknowledgement
within a few days.

## Scope

This repository contains the agentic-SDLC framework: documentation, skills,
and shell scripts (onboarding / bootstrap). In scope, among other things:

- command injection or unsafe handling of untrusted input in the shell scripts
- credentials or tokens leaked anywhere in the repository or its history
- supply-chain issues in anything the framework instructs seats to install or run

## Supported versions

Only the latest state of `main` is supported.
