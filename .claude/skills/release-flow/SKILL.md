---
name: release-flow
description: Prepare and sanity-check a Resolver release before running Resolver/deploy.sh — verifies MARKETING_VERSION/CURRENT_PROJECT_VERSION are in sync, summarizes what changed since the last version tag/commit for release notes, and reminds of the deploy.sh flow (version bump, Release xcodebuild, DMG, commit+push). Use when the user wants to cut a release, bump the version, or write release notes.
disable-model-invocation: true
---

# Release Flow

Helper for cutting a Resolver release. `Resolver/deploy.sh` itself is interactive (prompts for the new version
number) and does the real work — this skill prepares for it and drafts release notes, it does not replace it.

## Steps

1. **Check version consistency** before running `deploy.sh`:
   ```bash
   grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" Resolver.xcodeproj/project.pbxproj | sort -u
   ```
   All `MARKETING_VERSION` occurrences should match each other, likewise `CURRENT_PROJECT_VERSION` — `deploy.sh`
   updates every occurrence via `sed`, but if a previous run was interrupted they can drift.

2. **Find the last release point** to scope the changelog. This repo tags releases as plain commits with the
   version as the message (see `git log --oneline`, e.g. `1.3.5`, `v1.3.5`) rather than annotated git tags —
   confirm with `git log --oneline -20` before assuming a tag exists.

3. **Draft release notes** from the commit range since the last version commit:
   ```bash
   git log --oneline <last-version-commit>..HEAD
   ```
   Group into user-facing changes vs. internal/refactor, and write them in the same terse style as existing
   commit messages in this repo (see `git log`).

4. **Hand off to `deploy.sh`**: remind the user to run it from `Resolver/` (`cd Resolver && ./deploy.sh`) — it
   prompts for the new version, builds a Release universal binary (arm64+x86_64) via `xcodebuild`, packages a
   DMG, and commits+pushes. This skill does not run it — the version-number prompt and build are meant to be
   interactive/manual.

## Output

Present: current version, proposed next version (ask if unclear — this repo has no strict semver convention
visible in history), and a drafted changelog since the last version commit, formatted for the user to paste
wherever they publish release notes.
