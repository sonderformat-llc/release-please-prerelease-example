# Release-Please Prerelease and Release Example

This repository demonstrates how to implement a SOC 2 compliant release workflow using the [release-please-action](https://github.com/googleapis/release-please-action). The workflow automates version management, changelog generation, and GitHub release creation, ensuring a consistent and auditable release process.

## Overview

The release workflow consists of two main stages:
1. **Prerelease** - Creates release candidates (RC) for testing before final release
2. **Release** - Creates the final release after successful testing

Given all additional testing- and publish-workflows are implemented compliant, and the GitHub repository has properly configured branch protection rules. This template shows an approach which supports SOC 2 compliance by:
- Compatible with protected main branch rule (no direct commits to main)
- Maintaining a clear audit trail of all changes
- Enforcing a consistent release process
- Automating version management
- Providing traceability between code changes and releases
- Enforcing separation of duties between development and release processes
- Creating a controlled environment for testing through prereleases
- Providing evidence of testing before final release
- Generating comprehensive change management documentation
- Supporting access control through PR approval workflows
- Enabling risk assessment through the prerelease process

## Workflow Features

- **Automated Versioning**: Automatically increments version numbers based on [Conventional Commits](https://www.conventionalcommits.org/)
- **Changelog Generation**: Automatically creates and updates CHANGELOG.md with categorized changes
- **GitHub Releases**: Creates GitHub releases with appropriate tags
- **Version Synchronization**: Updates version information across multiple files
- **Prerelease Support**: Creates release candidates for testing before final release
- **Conditional Execution**: Runs different jobs based on whether it's a prerelease or final release

## How It Works

### Configuration Files

- `.github/prerelease-config.json`: Configuration for prerelease stage
- `.github/release-config.json`: Configuration for final release stage
- `.github/prerelease-manifest.json`: Tracks the prerelease version
- `.github/release-manifest.json`: Tracks the release version

### Workflow Stages

1. **Label Check**: Creates the necessary labels for release-please PRs
2. **Prerelease Preparation**: Creates or finalizes a prerelease pull request
3. **Prerelease Testing**: Runs tests before creating the prerelease
4. **Prerelease Creation**: Creates the prerelease and a subsequent release pull request
5. **Post-Prerelease Steps**: Runs any necessary steps after prerelease
6. **Release Creation**: Creates the final release
7. **Post-Release Steps**: Runs any necessary steps after release

### Version Management

In this example the workflow updates version information in:
- `frontend/version.txt`: Simple version tracking for the named `frontend` package
- `.github/prerelease-manifest.json`: Version manifest for release-please
- `custom-version-update-example/build.gradle.kts`: An additional file with a version marker, demonstrating how to keep arbitrary files in sync using the `extra-files` feature

### Named Package vs Root Package

This example uses a **named package** (`frontend`) instead of the root package (`.`).
This is the recommended approach for monorepos or when you want to track multiple packages.

**Key differences when using named packages:**

| Aspect | Root package (`.`) | Named package (e.g. `frontend`) |
|--------|-------------------|----------------------------------|
| Workflow output: tag name | `steps.release.outputs.tag_name` | `steps.release.outputs['frontend--tag_name']` |
| Workflow output: releases created | `steps.release.outputs.releases_created` | `steps.release.outputs.releases_created` (overall) or `steps.release.outputs['frontend--releases_created']` (per package) |
| Manifest key | `"."` | `"frontend"` |
| `jsonpath` in `release-config.json` extra-files | `"$[\".\"]"` | `"$.frontend"` |
| Version file location | `version.txt` (repo root) | `frontend/version.txt` |
| Changelog location | `CHANGELOG.md` (repo root) | `frontend/CHANGELOG.md` |

#### Why the `release-config.json` must update `prerelease-manifest.json`

When a final release PR is merged, release-please only updates the `release-manifest.json`.
Without additional configuration the `prerelease-manifest.json` is **not** updated, causing the
next prerelease to calculate an incorrect version (e.g. `1.9.0-rc.1` after releasing `2.0.0`).

The `extra-files` entry in `release-config.json` solves this by updating the
`prerelease-manifest.json` as part of the release PR:

```json
{
  "type": "json",
  "path": ".github/prerelease-manifest.json",
  "jsonpath": "$.frontend"
}
```

> **JSONPath note:** Named packages use simple dot notation (e.g. `$.frontend`).
> The root package uses bracket notation (`$["."]`) because `.` is a reserved
> character in JSONPath expressions — it must be quoted inside brackets.

This ensures both manifest files stay in sync after every release.

### Changelog Management

The CHANGELOG.md file is automatically updated based on the `changelog-sections` configuration in both the prerelease and release configuration files. The current configuration includes:

- Features (from `feat:` commits)
- Bug Fixes (from `fix:` commits)
- Code Refactoring (from `refactor:` commits)
- Miscellaneous Chores (from `chore:` commits)
- Build System and Dependencies (from `build:` commits)
- Documentation (from `docs:` commits)

Each section can be customized by modifying the `changelog-sections` array in the configuration files:

```json
"changelog-sections": [
  { "type": "feat", "hidden": false, "section": "Features" },
  { "type": "fix", "hidden": false, "section": "Bug Fixes" },
  { "type": "refactor", "hidden": false, "section": "Code Refactoring" },
  { "type": "chore", "hidden": false, "section": "Miscellaneous Chores" },
  { "type": "build", "hidden": false, "section": "Build System and Dependencies" },
  { "type": "docs", "hidden": false, "section": "Docs" }
]
```

You can add additional commit types, change section titles, or hide specific sections by setting `"hidden": true`. For more information on this, check the [Configuration File Reference](#Configuration-File-Reference) section.

## Usage

1. Push changes to the main branch with [Conventional Commits](https://www.conventionalcommits.org/)
2. The workflow automatically creates a prerelease pull request
3. When the prerelease PR is merged, a release candidate is created
4. After testing, the workflow creates a final release pull request
5. When the release PR is merged, the final release is created

## Implementation Details

The workflow is implemented using GitHub Actions and the release-please-action. It requires:
- GitHub repository permissions for contents, pull-requests, and repository-projects
- Conventional commit messages for proper changelog generation and version bumping
- Configuration files for prerelease and release stages

## Configuration File Reference

This section provides details on how to extend and modify the configuration files used by release-please.

### Key Configuration Options Explained

- **release-type**: Specifies the release strategy. Options include:
  - `simple`: Basic generic versioning
  - `node`: For Node.js projects
  - `python`: For Python projects
  - `java`: For Java projects
  - `maven`: For Maven projects
  - `go`: For Go projects
  - `rust`: For Rust projects
  - And many others (see [release-please documentation](https://github.com/googleapis/release-please/blob/main/docs/customizing.md))

- **prerelease**: Boolean flag to indicate if this is a prerelease configuration

- **prerelease-type**: The type of prerelease to create (e.g., `rc`, `beta`, `alpha`)

- **versioning**: The versioning strategy to use:
  - `prerelease`: For prerelease versioning (adds suffixes like `-rc.1`)
  - `default`: Standard semantic versioning

- **changelog-sections**: Defines how different commit types are categorized in the changelog:
  - `type`: The commit type (from conventional commits)
  - `hidden`: Whether to hide this section in the changelog
  - `section`: The section title in the changelog

- **packages**: Defines the package structure for monorepos or single packages:
  - `.`: Represents the root package (single-package repos)
  - `frontend`, `backend`, etc.: Named packages for monorepos
  - `type`: The package type (e.g., `generic`, `node`, `java`)
  - `extra-files`: Additional files to update with version information

- **extra-files**: Files to update during version changes:
  - `type`: The file type (`generic`, `json`, `xml`, etc.)
  - `path`: Path to the file
  - `jsonpath`: For JSON files, the path to the version field
  - `marker`: For generic files, a marker pattern to identify version strings

### Customization Examples

#### Adding Custom Changelog Sections

```json
"changelog-sections": [
  { "type": "feat", "hidden": false, "section": "Features" },
  { "type": "fix", "hidden": false, "section": "Bug Fixes" },
  { "type": "perf", "hidden": false, "section": "Performance Improvements" },
  { "type": "refactor", "hidden": false, "section": "Code Refactoring" },
  { "type": "test", "hidden": false, "section": "Testing" },
  { "type": "chore", "hidden": true, "section": "Miscellaneous Chores" }
]
```

#### Updating Version in Multiple Files

```json
"extra-files": [
  {
    "type": "json",
    "path": "package.json",
    "jsonpath": "$.version"
  },
  {
    "type": "xml",
    "path": "pom.xml",
    "xpath": "//project/version"
  },
  {
    "type": "generic",
    "path": "src/version.py",
    "marker": "VERSION = \"${version}\""
  }
]
```

#### Configuring for a Monorepo

```json
"packages": {
  "packages/core": {
    "component": "core",
    "version-file": "version.txt"
  },
  "packages/ui": {
    "component": "ui",
    "version-file": "version.txt"
  }
}
```

### Best Practices

1. **Use Consistent Release Types**: Choose a release type that matches your project's language and structure.

2. **Define Clear Changelog Sections**: Customize changelog sections to match your team's commit conventions.

3. **Update All Version References**: Ensure all files containing version information are included in `extra-files`.

For more detailed information, refer to the official documentation:
- [release-please-action](https://github.com/googleapis/release-please-action)
- [release-please configuration](https://github.com/googleapis/release-please/blob/main/docs/customizing.md)
