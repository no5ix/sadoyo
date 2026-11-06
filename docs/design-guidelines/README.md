# Design Guidelines

## Principles

- Prefer native macOS interaction and visual conventions.
- Reuse existing design tokens, typography, spacing, iconography, card styles, and shared controls before creating new variants.
- Keep related content visually grouped and unrelated sections clearly separated.
- Preserve consistent control geometry: hit target, icon alignment, corner radius, hover/focus shape, and spacing should match across equivalent actions.
- Make hover, pressed, disabled, selected, loading, unavailable, and permission-required states intentional and distinguishable.
- Do not imply an action is supported when the underlying service cannot perform it.
- Dynamic content must resize its container; do not silently drop important sections to satisfy a stale fixed height.
- Support keyboard and VoiceOver interaction, reduced motion/transparency where relevant, and localization-driven text expansion.

## Implementation

- Inspect existing SwiftUI/AppKit components and the closest comparable screen before adding a new control.
- Keep business logic and state transitions in their owning service/support layer, not embedded in presentation-only code.
- Use stable identities for repeated cards and lists. Never key interactive state by a mutable array index.
- Keep clickable regions aligned with their visible shapes; child controls must remain independently operable.
- Use real data in visual tests. Do not replace missing metadata or unavailable sensors with plausible-looking invented values.

## References

- Current design assets and product screenshots: [docs/design-reference](../design-reference/).
- Feature-specific visual tests and interaction evidence: [Testing](../testing/README.md).
- Native accessibility, permission, and platform guidance: [Permissions](../PERMISSIONS.md).
