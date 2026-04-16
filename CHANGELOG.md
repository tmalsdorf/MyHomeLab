# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Multi-environment setup support**: Configure all three environments (dev, uat, prod) in one `.env` file
- New `SETUP_ALL_ENVIRONMENTS` flag to create all inventories in one run
- Environment-specific variables: `K3S_MASTERS_DEV`, `K3S_NODES_UAT`, `K3S_ENABLED_PROD`, etc.
- `process_environment()` function in `setup.sh` for modular environment processing
- Pinned Python and Ansible collection versions for reproducible builds
- Added `inventory/group_vars/` for shared configuration across environments
- Added role README files for documentation
- Added `meta/main.yml` for ArgoCD role

### Changed
- `example.env` restructured with per-environment K3s configuration sections
- `setup.sh` now supports both single-environment and all-environments modes
- Simplified inventory files by moving common vars to `group_vars/`
- Fixed typo in `homelab.yml` ("privledges" → "privileges")
- Improved `Setup.md` with multi-environment documentation
- Removed dead code comments from `roles/prereq/tasks/main.yml`

### Fixed
- `requirements.txt` now pins specific versions
- `collections/requirements.yml` now includes version constraints
