# UI design guidelines

Read this document before UI development. Reuse the implementation in `native-app/App/DesignSystem/TacticalComponents.swift` and its `TacticalColors` and `TacticalTypography` definitions as the source of truth for colors, typography, spacing and sizing. Avoid copying token values into documentation or new views.

## Visual language and layout

Keep the dark HELLDIVERS 2 tactical identity, yellow emphasis for primary actions, clear information hierarchy and restrained decoration. Use `TacticalPageHeader` for secondary-page titles and the existing dashboard presentation for the overview. Keep action controls in content areas, aligned consistently, and use adaptive layouts for narrow windows and long translations. Use `TacticalPanel`, metrics and status badges for related evidence; distinguish unchecked, checking, success, warning, failure and uncertainty without inventing health. Approved reference images guide composition and tactical details, while actual service evidence determines all text, actions and states. Reuse `TacticalFlowMark` and `TacticalFlowStep` for restrained numbered and angled accents.

## Artwork and attribution

Keep the Dashboard hero unchanged unless explicitly requested. The shared `TacticalPageHeader` starfield, Earth sunrise, Super Earth emblem, left title and yellow divider are protected; do not replace or cover them with new illustrations. Use `TacticalFlowArtwork` for the first-run welcome, setup completion and game-launch preparation flows: it places artwork at a shared right-hand width and inset, hides it when controls need the space, and follows each source's aspect ratio without large empty bands. Different source proportions require different heights to show complete works without cropping. Preserve original artwork and aspect ratio; never crop, recolor or modify it without authorization. Do not add permanent artwork to the environment, performance, logs or FX-management pages. Decoration must not obscure text, compress controls or block actions. Record third-party authorship and permission, and visually review substantial changes with real App screenshots.

MOTR7 illustrations were supplied by the user for this App with permission attributed to the artist; the bundled JPEG files are unmodified copies. The user did not provide a general redistribution license. Use Democracy for welcome, Super Earth for completed setup and Soldier for game-launch preparation. `MOTR7Democracy.jpg` SHA-256 `ad891db7b12c024302dab5c3aecab3e52a0dd64e541509a9b0d272245b0e16db`; `MOTR7SuperEarth.jpg` SHA-256 `26fa9dda25faf193d8ea20e1a31f0c05a1ec15570dddd36c11af1e9c4f2d738c`; `MOTR7Soldier.jpg` SHA-256 `02587ff4d4be42575a15bb9f65d1419503e8dcc7b34a4b1e2aee55d43ffe3acf`.

The completion presentation requires a real completed setup and an inspection plan bound to the currently selected FX and Guest boot; it lists the plan's own observations. Game-launch progress displays actual completed workflow steps and live service state, preserving cancellation, error and retry controls. A process, fixture or screenshot cannot establish game, EAC or multiplayer acceptance.

## Actions and refresh

Use `TacticalButton` and `TacticalButtonStyle` for primary and secondary actions, preserving hover, pressed, focus, disabled and loading feedback. Convey success and failure using actual service results. Avoid duplicate actions. Prefer event-driven updates and existing detection actions over independent refresh. When an independent snapshot refresh is necessary, place `TacticalRefreshButton` at the right of the content toolbar; it uses existing AppState and TaskManager, disables repeat requests and displays progress. Scoped scans and global snapshots have different purposes and must be labelled accordingly. Do not put action buttons beside page titles.

## Loading and dialogs

Use the shared button loading state or a native progress indicator for ongoing work; bind it to the existing service/task state. Show real errors and recovery options. Use sheets or dialogs for credentials, target selection, important conflicts and consequential confirmation; retain existing safeguards and avoid unnecessary modal interruptions.

## Localization and accessibility

Maintain all ten existing languages through the localization resources. User-visible product names are `绝地潜兵 2 FX 启动器` and `HELLDIVERS 2 FX Launcher`; `HD2FXNative` is an internal engineering name. Avoid hardcoded user-visible prose; test long text at narrow widths without truncating meaningful information. Ordinary visual iterations review Chinese and English in both themes and window widths; widen the review for localization-system or other-language layout changes. Label controls for VoiceOver, hide decorative icons and artwork, preserve keyboard focus and shortcuts, and do not convey status by color alone.

## New page checklist

- Read AGENTS.md and this guide; reuse shared components and design tokens.
- Check title, margins, action placement, card hierarchy and narrow layouts.
- Check for duplicate actions and determine whether refresh is necessary.
- Verify hover, pressed, disabled, loading, success and error states where applicable.
- Check VoiceOver labels, keyboard navigation and all ten language resources; review Chinese and English layouts and widen the review where appropriate.
- Build and run appropriate tests; inspect real App screenshots for substantial visual changes and report any missing verification honestly.
