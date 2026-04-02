# CI Admin

This repo contains scripts to administrate the CI infrastructure at the Eclipse Foundation.

Most scripts will not work without access to the password store or the internal network.


- [CI Admin](#ci-admin)
  - [Quick Start with ci-adm CLI](#quick-start-with-ci-adm-cli)
  - [Installation](#installation)
    - [Automatic Installation (Recommended)](#automatic-installation-recommended)
    - [Manual Usage](#manual-usage)
  - [Usage](#usage)
    - [CLI Syntax](#cli-syntax)
    - [Available Modules](#available-modules)
    - [Usage Examples](#usage-examples)
      - [GitHub Module](#github-module)
      - [GitLab Module](#gitlab-module)
      - [GPG Module](#gpg-module)
      - [Nexus Module](#nexus-module)
      - [Password Store (pass) Module](#password-store-pass-module)
      - [Matrix Module](#matrix-module)
      - [SonarCloud Module](#sonarcloud-module)
      - [Project Management Module](#project-management-module)
      - [GitLab Runner Module](#gitlab-runner-module)
      - [Service Accounts Module](#service-accounts-module)
      - [Maven Central / Sonatype Module](#maven-central--sonatype-module)
      - [Projects Storage Module](#projects-storage-module)
      - [Build Tools Module](#build-tools-module)
  - [Dependencies](#dependencies)
  - [Playwright Installation](#playwright-installation)
  - [Uninstallation](#uninstallation)
  - [Contributing](#contributing)
  - [AI-Assisted Development](#ai-assisted-development)
  - [License](#license)


## Quick Start with ci-adm CLI

The easiest way to use the CI Admin tools is through the unified CLI interface:

```bash
# Install the CLI tool (automatic detection of best location)
./install.sh

# Or install to a specific location
./install.sh ~/.local/bin

# Get help
ci-adm help

# List all available commands
ci-adm list

# Get help for a specific module
ci-adm help github
```

## Installation

### Automatic Installation (Recommended)

The install script automatically detects the best installation directory:
- `~/.local/bin` for regular users (no sudo required)

```bash
# Auto-detect installation location
./install.sh

# Or specify a custom directory
./install.sh ~/my/custom/bin
```

Make sure the installation directory is in your PATH. If not, add this to your `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="$PATH:~/.local/bin"
```

### Manual Usage

You can also run scripts directly from their respective directories without installing the CLI.

## Usage

### CLI Syntax

```bash
ci-adm <module> <command> [arguments...]
```

### Available Modules

| Module | Description |
|--------|-------------|
| `github` | GitHub integration management |
| `gitlab` | GitLab integration management |
| `gpg` | GPG key and signing management |
| `nexus` | Nexus repository management |
| `pass` | Password store management |
| `matrix` | Matrix bot management |
| `sonarcloud` | SonarCloud project management |
| `project` | Project configuration management |
| `gitlab-runner` | GitLab runner provisioning |
| `service-accounts` | Service account management |
| `central-sonatype` | Maven Central / Sonatype setup |
| `projects-storage` | Projects storage setup |
| `buildtools` | Build tools management |

### Usage Examples

#### GitHub Module

```bash
# Setup GitHub bot for a project
ci-adm github setup-bot technology.cbi

# Create GitHub webhook
ci-adm github create-webhook technology.cbi

# Setup OtterDog
ci-adm github setup-otterdog technology.cbi

# Deploy SSH key
ci-adm github deploy-key technology.cbi

# Generate GitHub credentials
ci-adm github gen-credentials technology.cbi
```

#### GitLab Module

```bash
# Create GitLab bot user
ci-adm gitlab create-bot technology.cbi

# Create GitLab webhook
ci-adm gitlab create-webhook technology.cbi

# Setup Jenkins-GitLab integration
ci-adm gitlab setup-jenkins technology.cbi

# Setup GitLab runner
ci-adm gitlab setup-runner technology.cbi

# Setup license vetting workflow
ci-adm gitlab setup-license-vetting technology.cbi

# GitLab admin commands
ci-adm gitlab admin --help
```

#### GPG Module

```bash
# Setup GPG signing for a project
ci-adm gpg setup-signing technology.cbi

# Change GPG key passphrase
ci-adm gpg change-passphrase technology.cbi

# GPG key administration
ci-adm gpg key-admin --help
```

#### Nexus Module

```bash
# Create Nexus repositories for a project
ci-adm nexus create-repos technology.cbi
```

#### Password Store (pass) Module

```bash
# Add credentials
ci-adm pass add-creds technology.cbi

# Add GPG credentials
ci-adm pass add-creds-gpg technology.cbi

# Generate SSH key
ci-adm pass gen-ssh-key technology.cbi

# Change SSH key passphrase
ci-adm pass change-ssh-passphrase technology.cbi

# Show password store statistics
ci-adm pass stats
```

#### Matrix Module

```bash
# Setup Matrix bot
ci-adm matrix setup-bot technology.cbi

# Matrix administration
ci-adm matrix admin --help
```

#### SonarCloud Module

```bash
# Create SonarCloud project
ci-adm sonarcloud create-project technology.cbi

# Create SonarCloud project token
ci-adm sonarcloud create-token adoptium
```

#### Project Management Module

```bash
# Check secrets structure
ci-adm project check-secrets technology.cbi

# Fetch projects from API
ci-adm project fetch-api

# Show project statistics
ci-adm project stats

# Rename a project
ci-adm project rename old.project new.project
```

#### GitLab Runner Module

```bash
# Provision GitLab runner (GRAC)
ci-adm gitlab-runner provision --help
```

#### Service Accounts Module

```bash
# Setup PyPI service account
ci-adm service-accounts setup-pypi technology.cbi
```

#### Maven Central / Sonatype Module

```bash
# Setup Maven Central publishing
ci-adm central-sonatype setup technology.cbi
```

#### Projects Storage Module

```bash
# Setup projects storage
ci-adm projects-storage setup technology.cbi
```

#### Build Tools Module

```bash
# Add new Maven version
ci-adm buildtools add-maven-version 3.9.5

# Check JDK configuration
ci-adm buildtools check-jdk --help
```

## Dependencies

* [bash 4](https://www.gnu.org/software/bash/)
* [curl](https://curl.se/)
* [docker](https://www.docker.com)
* [git](https://git-scm.com)
* [jq](https://stedolan.github.io/jq/)
* [pass](https://www.passwordstore.org)

## Playwright Installation

For scripts that use Playwright (automated browser interactions):

```shell
sudo apt install oathtool
sudo apt install python-is-python3
python -m pip install --upgrade pip
python -m pip install playwright 
python -m pip install pyperclip
playwright install
```

## Uninstallation

To uninstall the ci-adm CLI:

```bash
# If installed in system directory
sudo rm /usr/local/bin/ci-adm

# If installed in user directory
rm ~/.local/bin/ci-adm
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to this project.

## AI-Assisted Development

Parts of this codebase were developed with the assistance of AI tools including GitHub Copilot. These tools helped accelerate development while maintaining code quality and consistency with Eclipse Foundation services.

## License

Copyright (c) 2026 Eclipse Foundation and others.

This program and the accompanying materials are made available under the terms of the Eclipse Public License 2.0 which is available at http://www.eclipse.org/legal/epl-v20.html

SPDX-License-Identifier: EPL-2.0


