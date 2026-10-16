<!--
Release PR: dev -> main. Opened and merged by the repo owner only.
Open with: .../compare/main...dev?template=release.md
Title: release: mobile vX.Y.Z+B   (must match the pubspec.yaml `version:` line)
Merge method: MERGE COMMIT (never squash or rebase: main and dev would diverge).
After merge: annotated tag on main: mobile-v<pubspec version>  (e.g. mobile-v1.0.0+1; hotfix: ...-hotfix.N)
-->

## Release

- Version / tag: `mobile-vX.Y.Z+B`
- `dev` SHA being promoted: `<sha>`
- Phases / PRs in this release: <list>

## Promotion checklist

- [ ] CI is green on the `dev` SHA above (`CI Gate`, including the full test run).
- [ ] Qase run on the `staging` flavor is done for every phase in the release (after mobile 408): <link>.
- [ ] `pubspec.yaml` `version:` is bumped (X.Y.Z+B, build number strictly higher than the last uploaded build) and matches the title and tag.
- [ ] After the tag: upload the AAB to Play internal testing (mobile 409+) and confirm it is processed.
- [ ] No secrets in the diff (`google-services.json`, keystores, `.env`, tokens); gitleaks is green.

## Rollback note

- Previous released tag / Play build: `<mobile-v...>`
