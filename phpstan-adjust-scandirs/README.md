# phpstan-adjust-scandirs

## About

**phpstan-adjust-scandirs** adjusts PHPStan NEON configuration file
to set `scanDirectories` and `excludePaths` according to the environment, e.g., local, CI/CD.

This script helps to adapt PHPStan config tailored to environment-specific directory scanning needs.

## Overview

- Validates scan directories for existence and readability.
- Merges input with existing `scanDirectories` and `excludePaths` in the NEON config.
- Removes nested directories to only keep highest-level paths.
- Outputs the updated NEON configuration or writes it in-place.

## Usage

`phpstan-adjust-scandirs.php --config=phpstan.neon --scan=dir{PATH_SEPARATOR}dir [--exclude=dir{PATH_SEPARATOR}dir]`

`PATH_SEPARATOR` is `:` on Unix-like systems.

- `--config`: Path to the PHPStan NEON configuration file to modify.
- `--scan`: List of directories for PHPStan to scan, separated by system `PATH_SEPARATOR`.
- `--exclude`: Optional list of directories to exclude from analysis, also separated by `PATH_SEPARATOR`.
- `--inplace`: Update PHPStan NEON configuration file in-place (default: output to stdout).

## License

MIT License. See [LICENSE](LICENSE) for details.
