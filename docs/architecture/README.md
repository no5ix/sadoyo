# Architecture Documentation

Use this directory for deeper architecture maps and subsystem ownership notes.

Start with the repository-level [Architecture Guide](../../ARCHITECTURE.md). Keep detailed documents grounded in current source paths and update them when ownership or data flow changes.

Suggested topics:
- Application startup and feature lifecycle.
- Feature catalog, preferences, and settings backup.
- Status-item, app-panel, and Dynamic Island presentation routing.
- Now Playing adapter, player discovery, metadata, and per-player command routing.
- System monitoring and hardware/service boundaries.
- Permission, helper-process, and signing boundaries.

Do not create a second source of truth for behavior already documented in code or another guide. Link to the owning code and tests.
