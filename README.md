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
2. **Prerelease Preparation** (`release.yaml`): Runs release-please once for all packages; outputs per-component tags
3. **Create Release PRs** (`release.yaml`): When any RC tag is produced, runs release-please with `release-config.json` to open the final-release PRs
4. **Component Release Workflows** (called in parallel from `release.yaml`):
   - `release-frontend.yaml` — frontend-specific tests, build, and deploy
   - `release-backend.yaml` — backend-specific tests, build, and deploy
   - `release-admin.yaml` — admin-specific tests, build, and deploy

Each component workflow receives two inputs from the orchestrator:
- `releases_created` — whether release-please created a release on this run
- `tag_name` — the tag produced for that specific package (e.g. `frontend-v1.11.0-rc.1`)

Inside each component workflow the same logic applies:
- **No release created** (`releases_created == 'false'`): run component tests
- **RC tag** (`tag_name` contains `rc`): build and deploy the prerelease
- **Final tag** (`tag_name` does not contain `rc`): build and deploy to production

```
push to main
    |
    v
label-check
    |
    v
prerelease-prep (release-please -> outputs: frontend_tag, backend_tag, admin_tag)
    |
    +---> create-release-prs  (if any tag is RC -> open final-release PRs)
    |
    +---> frontend-release  ---> release-frontend.yaml (tests / prerelease / release)
    +---> backend-release   ---> release-backend.yaml  (tests / prerelease / release)
    +---> admin-release     ---> release-admin.yaml    (tests / prerelease / release)
```

### Version Management

In this example the workflow updates version information in:
- `frontend/version.txt`: Version tracking for the `frontend` package
- `backend/version.txt`: Version tracking for the `backend` package
- `admin/version.txt`: Version tracking for the `admin` package
- `.github/prerelease-manifest.json`: Version manifest for release-please
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

#### Multi-Package Workflow Outputs and Component Workflows

When multiple packages are defined, each exposes its own `<path>--tag_name` output.
The orchestrator (`release.yaml`) collects them and passes each one to the matching
component workflow via `workflow_call`:

```yaml
# In release.yaml — expose per-package tags
outputs:
  releases_created: ${{ steps.release.outputs.releases_created }}
  frontend_tag: ${{ steps.release.outputs['frontend--tag_name'] }}
  backend_tag:  ${{ steps.release.outputs['backend--tag_name'] }}
  admin_tag:    ${{ steps.release.outputs['admin--tag_name'] }}

# Call each component workflow in parallel
frontend-release:
  needs: [ prerelease-prep ]
  uses: ./.github/workflows/release-frontend.yaml
  with:
    releases_created: ${{ needs.prerelease-prep.outputs.releases_created }}
    tag_name: ${{ needs.prerelease-prep.outputs.frontend_tag }}
```

Inside each component workflow (`release-frontend.yaml`, `release-backend.yaml`,
`release-admin.yaml`) the job conditions use the per-component `inputs.tag_name`:

```yaml
# Component-specific prerelease (RC) step
prerelease:
  if: ${{ inputs.releases_created == 'true' && contains(inputs.tag_name, 'rc') }}

# Component-specific final release step
release:
  if: ${{ inputs.releases_created == 'true' && !contains(inputs.tag_name, 'rc') }}
```

This pattern keeps the release-please orchestration in one place while giving each
component its own workflow file for tests, builds, and deployment steps.

#### Why the `release-config.json` must update `prerelease-manifest.json`

When a final release PR is merged, release-please only updates the `release-manifest.json`.
Without additional configuration the `prerelease-manifest.json` is **not** updated, causing the
next prerelease to calculate an incorrect version (e.g. `1.9.0-rc.1` after releasing `2.0.0`).

Each package in `release-config.json` has an `extra-files` entry that updates its own key in
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
