# Registry Update Script

This directory contains automation scripts for maintaining the plugin registry.

## update-registry.js

Automatically scans plugin directories and updates `registry.json` with current plugin metadata.

### How It Works

1. Scans all directories in the repository root
2. Looks for `manifest.json` in each directory
3. Extracts registry-relevant fields (id, name, version, author, etc.)
4. Generates an updated `registry.json` with all discovered plugins
5. Sorts plugins alphabetically by ID for consistent output

### Automatic Updates

The script runs automatically via GitHub Actions when:
- A `manifest.json` file is modified in any plugin directory
- Changes are pushed to the `main` branch
- Manually triggered via workflow dispatch

See [`.github/workflows/update-registry.yml`](../.github/workflows/update-registry.yml) for workflow details.

## Adding New Plugins

When you add a new plugin:

1. Create a directory with your plugin files
2. Include a valid `manifest.json` with required fields:
   - `id`: Unique plugin identifier
   - `name`: Human-readable plugin name
   - `version`: Semantic version (e.g., "1.0.0")
   - `author`: Plugin author name
   - `description`: Brief plugin description
   - `repository`: Repository URL
   - `minNoctaliaVersion`: Minimum Noctalia version required
   - `license`: License identifier (e.g., "MIT")

3. The registry will automatically update when you push to main

## Fields Included in Registry

The registry extracts these fields from each plugin's manifest:
- `id`
- `name`
- `version`
- `author`
- `description`
- `repository`
- `minNoctaliaVersion`
- `license`

Other manifest fields (like `entryPoints`, `dependencies`, `metadata`) are not included in the registry to keep it lightweight.
