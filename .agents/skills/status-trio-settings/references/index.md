# status-trio-settings references

Generated from `SettingsSemanticCatalog` at schema version 1. Regenerate rather
than hand-editing the JSON.

## Files

| File | Contents |
|---|---|
| `settings-schema.json` | User-visible setting descriptors, including the DIY status-strip layout and indicator styles. |
| `feature-registry.json` | User-facing features, their parent `requires`, and the mutations they emit. |
| `capability-registry.json` | Environment capabilities (`ui.liquidGlass`, `hardware.hasBattery`, `permission.bluetooth`, `helper.ready`, …). |
| `action-registry.json` | One-shot operations (never auto-run by a profile). |
| `dev-profile.schema.json` | JSON Schema for `.dev-profile.json`. |
| `modules/<module>.md` | Per-module setting tables: general, panel, icon, hardware, battery, bluetooth, audio, brightness. |
| `dependency-rules.md` | Dependency, conflict and connected-change rules in prose. |
| `examples.md` | Worked `.dev-profile.json` examples. |

## Regenerating

The exporter lives at
`Sources/StatusTrioCore/Settings/Schema/SettingsSchemaExporter.swift` and is pure
`Foundation`. To refresh the artifacts, run from the repository root:

```bash
STATUS_TRIO_SCHEMA_EXPORT_DIR="$PWD/.agents/skills/status-trio-settings/references" \
  bash scripts/test.sh 'SettingsSchemaArtifactConsistencyTests/exportSchemaOnRequest'
```

Change the catalog and regenerate instead of editing the JSON or module tables.

## Coverage note

This cut covers the modules and complex cases named by the settings-semantic
plan. The Phase 0 inventory (`docs/settings/settings-inventory.md`) remains the
checklist for the remaining user-visible settings to describe as the catalog
grows.
