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

Each component has its own set of configuration and manifest files:

| Component | Prerelease config | Prerelease manifest | Release config | Release manifest |
|-----------|-------------------|---------------------|----------------|-----------------|
| frontend  | `prerelease-config-frontend.json` | `prerelease-manifest-frontend.json` | `release-config-frontend.json` | `release-manifest-frontend.json` |
| backend   | `prerelease-config-backend.json`  | `prerelease-manifest-backend.json`  | `release-config-backend.json`  | `release-manifest-backend.json`  |
| admin     | `prerelease-config-admin.json`    | `prerelease-manifest-admin.json`    | `release-config-admin.json`    | `release-manifest-admin.json`    |

Keeping the configs and manifests separate per component avoids conflicts when two
component workflows are triggered simultaneously by changes to different directories.

### Workflow Stages

Each component has a fully standalone workflow file that is triggered independently
when files in that component's directory are pushed to `main`.

```
push frontend/** to main           push backend/** to main            push admin/** to main
         |                                  |                                  |
         v                                  v                                  v
release-frontend.yaml              release-backend.yaml               release-admin.yaml
  label-check                        label-check                        label-check
  prerelease-prep                    prerelease-prep                    prerelease-prep
  create-release-pr                  create-release-pr                  create-release-pr
  prerelease-test                    prerelease-test                    prerelease-test
  prerelease                         prerelease                         prerelease
  post-prerelease                    post-prerelease                    post-prerelease
  release                            release                            release
  post-release                       post-release                       post-release
```

Inside each workflow the jobs are conditioned on the release-please output for that component:
- **No release created** (`releases_created == 'false'`): run component tests
- **RC tag** (`tag_name` contains `rc`): build/deploy the prerelease and open final-release PR
- **Final tag** (`tag_name` does not contain `rc`): build/deploy to production

### Version Management

In this example the workflow updates version information in:
- `frontend/version.txt`: Version tracking for the `frontend` package
- `backend/version.txt`: Version tracking for the `backend` package
- `admin/version.txt`: Version tracking for the `admin` package
- `.github/prerelease-manifest-{component}.json`: Per-component prerelease version manifest
- `custom-version-update-example/build.gradle.kts`: An additional file with a version marker, demonstrating how to keep arbitrary files in sync using the `extra-files` feature (attached to the `frontend` package)

### Named Package vs Root Package

This example uses **named packages** (`frontend`, `backend`, `admin`) instead of the root package (`.`).
This is the recommended approach for monorepos with multiple independently versioned packages.

**Key differences when using named packages:**

| Aspect | Root package (`.`) | Named package (e.g. `frontend`) |
|--------|-------------------|----------------------------------|
| Workflow output: tag name | `steps.release.outputs.tag_name` | `steps.release.outputs['frontend--tag_name']` |
| Workflow output: releases created | `steps.release.outputs.releases_created` | `steps.release.outputs.releases_created` (overall) or `steps.release.outputs['frontend--releases_created']` (per package) |
| Manifest key | `"."` | `"frontend"` |
| `jsonpath` in `release-config.json` extra-files | `"$[\".\"]"` | `"$.frontend"` |
| Version file location | `version.txt` (repo root) | `frontend/version.txt` |
| Changelog location | `CHANGELOG.md` (repo root) | `frontend/CHANGELOG.md` |

#### Standalone Component Workflows

Each component workflow is fully independent. It runs release-please with its own config and
manifest files and uses the `<path>--tag_name` output pattern to read back the tag for that
specific package:

```yaml
# In release-frontend.yaml
prerelease-prep:
  outputs:
    releases_created: ${{ steps.release.outputs.releases_created }}
    tag_name: ${{ steps.release.outputs['frontend--tag_name'] }}
  steps:
    - id: release
      uses: googleapis/release-please-action@...
      with:
        config-file: ".github/prerelease-config-frontend.json"
        manifest-file: ".github/prerelease-manifest-frontend.json"
```

Downstream jobs read `needs.prerelease-prep.outputs.tag_name` directly:

```yaml
prerelease:
  if: ${{ needs.prerelease-prep.outputs.releases_created == 'true' && contains(needs.prerelease-prep.outputs.tag_name, 'rc') }}

release:
  if: ${{ needs.prerelease-prep.outputs.releases_created == 'true' && !contains(needs.prerelease-prep.outputs.tag_name, 'rc') }}
```

#### Why the `release-config-{component}.json` must update `prerelease-manifest-{component}.json`

When a final release PR is merged, release-please only updates `release-manifest-{component}.json`.
Without additional configuration the `prerelease-manifest-{component}.json` is **not** updated, causing the
next prerelease to calculate an incorrect version (e.g. `1.9.0-rc.1` after releasing `2.0.0`).

Each component's `release-config-{component}.json` has an `extra-files` entry that updates its own
key in the corresponding `prerelease-manifest-{component}.json` as part of the release PR:

```json
{
  "type": "json",
  "path": ".github/prerelease-manifest-frontend.json",
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
