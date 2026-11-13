---
name: release
description: Bump the app version in pubspec.yaml, commit, tag, and push so CI publishes a self-updating release APK. Use when the user wants to deploy or ship an app update.
argument-hint: "[patch|minor|major|X.Y.Z]"
disable-model-invocation: true
---

# Release the app

Publish a new OpenGym release by following the **Releasing** section of
`AGENTS.md`. Pushing the tag triggers `.github/workflows/release.yml`, which
tests, builds, signs, and publishes the APK the in-app updater installs.

Argument: `$ARGUMENTS`. It sets the version name bump:

- empty or `patch`: `1.0.11` → `1.0.12` (the usual case)
- `minor`: `1.0.11` → `1.1.0`
- `major`: `1.0.11` → `2.0.0`
- an explicit `X.Y.Z`: use it as the version name, but it must be greater than
  the current one

The `+build` number **always** goes up by exactly 1 from the highest build
number ever released, whatever the argument. It is never reset.

## 1. Preflight

Run these and stop to ask the user if anything looks wrong:

```bash
git branch --show-current
git status --short
git fetch --tags origin
grep -m1 '^version:' pubspec.yaml
git tag --list 'v*' --sort=-v:refname | head -5
```

- **Branch**: previous releases were tagged on `main`. If the current branch
  isn't `main`, tell the user and ask whether to release from it anyway or
  switch first. Don't switch or merge without being asked.
- **Remote**: if the branch is behind its upstream, stop and tell the user.
- **Build number**: take the highest `+N` across both pubspec and all `v*`
  tags. The new build number is that plus 1. If pubspec and the latest tag
  disagree, say so before continuing.
- **Working tree**: other uncommitted changes are fine and stay out of the
  release commit. If the five generated plugin registrants under `linux/`,
  `macos/`, or `windows/` show up, confirm that
  `git diff --ignore-all-space --stat -- linux/ macos/ windows/` is empty, then
  `git checkout -- linux/ macos/ windows/`.

## 2. Verify

```bash
flutter analyze
flutter test
```

CI runs `flutter test` before building, and a failure there leaves a pushed
tag with no release. If either command fails, stop and report the failures.
Don't bump anything.

## 3. Bump

Edit only the `version:` line in `pubspec.yaml` to `X.Y.Z+N`. Then check that
nothing else changed in that file:

```bash
git diff pubspec.yaml
```

## 4. Confirm

Show the user the old and new version, the branch, and the commit that will be
tagged. Ask for confirmation before pushing, because a pushed tag publishes a
release to every installed copy.

## 5. Commit, tag, push

Stage `pubspec.yaml` explicitly. Never use `git commit -am` or `git add -A`.
Don't add co-author or generated-by trailers.

```bash
git add pubspec.yaml
git commit -m "chore: release X.Y.Z+N"
git tag vX.Y.Z+N
git push
git push origin vX.Y.Z+N
```

The tag must equal the pubspec version character for character, with a
leading `v` and the `+N` included. Push the new tag by name rather than with
`--tags`, so stray local tags stay local.

## 6. Report

Tell the user the new version and tag, and give the Actions link if `gh` is
available:

```bash
gh run list --workflow=release.yml --limit 1
```

Don't wait on the run unless the user asks. If they do, use
`gh run watch <id>`. When it finishes, check that the release isn't a draft or
prerelease and has exactly one `.apk` asset:
`gh release view vX.Y.Z+N`.
