# UI design guidelines

Read this document before UI development. Reuse the implementation in `native-app/App/DesignSystem/TacticalComponents.swift` and its `TacticalColors` and `TacticalTypography` definitions as the source of truth for colors, typography, spacing and sizing. Avoid copying token values into documentation or new views.

## Visual language and layout

Keep the dark HELLDIVERS 2 tactical identity, yellow emphasis for primary actions, clear information hierarchy and restrained decoration. Use `TacticalPageHeader` for secondary-page titles and the existing dashboard presentation for the overview. Keep action controls in content areas, aligned consistently, and use adaptive layouts for narrow windows and long translations. Use `TacticalPanel`, metrics and status badges for related evidence; distinguish unchecked, checking, success, warning, failure and uncertainty without inventing health.

## Actions and refresh

Use `TacticalButton` and `TacticalButtonStyle` for primary and secondary actions, preserving hover, pressed, focus, disabled and loading feedback. Convey success and failure using actual service results. Avoid duplicate actions. Prefer event-driven updates and existing detection actions over independent refresh. When an independent snapshot refresh is necessary, place `TacticalRefreshButton` at the right of the content toolbar; it uses existing AppState and TaskManager, disables repeat requests and displays progress. Scoped scans and global snapshots have different purposes and must be labelled accordingly. Do not put action buttons beside page titles.

## Loading and dialogs

Use the shared button loading state or a native progress indicator for ongoing work; bind it to the existing service/task state. Show real errors and recovery options. Use sheets or dialogs for credentials, target selection, important conflicts and consequential confirmation; retain existing safeguards and avoid unnecessary modal interruptions.

## Localization and accessibility

Maintain all ten existing languages through the localization resources. Avoid hardcoded user-visible prose; test long text at narrow widths without truncating meaningful information. Label controls for VoiceOver, hide decorative icons and artwork, preserve keyboard focus and shortcuts, and do not convey status by color alone.

## New page checklist

- Read AGENTS.md and this guide; reuse shared components and design tokens.
- Check title, margins, action placement, card hierarchy and narrow layouts.
- Check for duplicate actions and determine whether refresh is necessary.
- Verify hover, pressed, disabled, loading, success and error states where applicable.
- Check VoiceOver labels, keyboard navigation and all ten languages, including long translations.
- Build and run appropriate tests; inspect real App screenshots for substantial visual changes and report any missing verification honestly.
