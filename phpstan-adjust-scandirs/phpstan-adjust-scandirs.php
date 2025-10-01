#!/usr/bin/env php
<?php

// SPDX-FileCopyrightText: 2025 Icinga GmbH
// SPDX-License-Identifier: MIT

// phpcs:disable PSR1.Files.SideEffects.FoundWithSymbols

declare(strict_types=1);

require __DIR__ . '/vendor/autoload.php';

use Nette\Neon\Neon;

function usage(): void
{
    echo <<<EOF
Adjusts PHPStan NEON configuration file to set scanDirectories and excludePaths
according to the environment, e.g., local, CI/CD.

Usage:
  phpstan-adjust-scandirs.php --config=phpstan.neon --scan=dir{PATH_SEPARATOR}dir [--exclude=dir{PATH_SEPARATOR}dir]

PATH_SEPARATOR is : on Unix-like systems.

Options:
  --config  Path to phpstan.neon configuration file (required)
  --scan    Directories to scan, separated by PATH_SEPARATOR (required)
  --exclude Directories to exclude from analysis, separated by PATH_SEPARATOR (optional)
  --inplace Update phpstan.neon configuration file in-place (default: output to stdout)

This script merges provided scan and exclude directories with the existing config,
validates directory readability, removes nested directories to keep only the highest-level,
and outputs the updated NEON config or writes it in-place.

EOF;
}

$options = getopt('', ['config:', 'scan:', 'exclude::', 'inplace', 'help']);
if (! ($options['help'] ?? true)) {
    usage();
    exit(0);
}
if (empty($options['config']) || empty($options['scan'])) {
    usage();
    exit(1);
}

$configFile = $options['config'];
$scanDirsRaw = $options['scan'];
$excludeDirsRaw = $options['exclude'] ?? '';
$inPlace = ! ($options['inplace'] ?? true);

$diff = [];

$scanDirs = explode(PATH_SEPARATOR, $scanDirsRaw);
foreach ($scanDirs as $dir) {
    if (! is_dir($dir)) {
        fwrite(STDERR, "Error: Directory does not exist: $dir\n");
        exit(1);
    }
    if (! is_readable($dir)) {
        fwrite(STDERR, "Error: Directory not readable: $dir\n");
        exit(1);
    }
    $diff[] = "+ $dir";
}

try {
    $config = Neon::decodeFile($configFile);
    if ($config === null) {
        throw new Exception("Config is empty");
    }
} catch (Throwable $e) {
    fwrite(STDERR, "Error: Failed to decode NEON config: " . $e->getMessage() . "\n");
    exit(1);
}

foreach ((array) ($config['parameters']['scanDirectories'] ?? []) as $existing) {
    if (is_dir($existing) && is_readable($existing)) {
        $scanDirs[] = $existing;
        $diff[] = "$existing (unchanged)";
    } else {
        $diff[] = "- $existing (not readable)";
    }
}

$config['parameters']['scanDirectories'] = array_unique(reduceBasePaths($scanDirs));

$excludeDirs = array_filter(explode(PATH_SEPARATOR, $excludeDirsRaw));
if (! empty($excludeDirs)) {
    if (isset($config['parameters']['excludePaths']['analyseAndScan'])) {
        $config['parameters']['excludePaths']['analyseAndScan'] = array_unique(array_merge(
            $config['parameters']['excludePaths']['analyseAndScan'],
            $excludeDirs
        ));
    } else {
        $config['parameters']['excludePaths']['analyseAndScan'] = $excludeDirs;
    }
}

fwrite(STDERR, implode(PHP_EOL, $diff) . PHP_EOL);

$config = Neon::encode($config, true);
if ($inPlace) {
    if (@file_put_contents($configFile, $config) === false) {
        throw new Exception("Failed to write to $configFile");
    }
} else {
    echo $config;
}

/**
 * Removes all nested (child) paths from an array, leaving only base (parent) paths.
 *
 * Given an array of directory paths, this function excludes any path that is a subdirectory
 * of another path present in the array.
 *
 * Example:
 *   Input:  ['/vendor', '/app', '/vendor/app']
 *   Output: ['/app', '/vendor']
 *
 * @param string[] $paths Array of absolute or relative directory paths.
 * @return string[] Array including only the highest-level (non-nested) paths.
 */
function reduceBasePaths(array $paths): array
{
    // Sort to ensure parent directories come before children.
    sort($paths);

    $result = [];
    foreach ($paths as $path) {
        $isChild = false;
        foreach ($result as $base) {
            // Check if $path is a child of $base
            if (str_starts_with($path, $base . DIRECTORY_SEPARATOR)) {
                $isChild = true;
                break;
            }
        }
        if (! $isChild) {
            $result[] = $path;
        }
    }
    return $result;
}
