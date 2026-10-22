# UI, UX, and Human Interface Guidelines Audit

Reviewed October 22, 2026. This record covers the development working tree after the 0.2.0 release. It records source review, implementation changes, and the limits of the available verification. Native accessibility acceptance is pending.

## Apple Guidance Used

All references below are official Apple Human Interface Guidelines pages retrieved during this review.

| Area | Applicable Guidance | Source |
| --- | --- | --- |
| Buttons | Use a prominent style for the most likely action. Keep the number of prominent actions small, and make each button's purpose clear. | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) |
| Menus | Include app commands in the menu bar even when they are available elsewhere. Menus expose commands and their shortcuts to keyboard users. | [The Menu Bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) |
| Keyboard Access | Support Full Keyboard Access and familiar shortcuts. Escape cancels the current action; Command-period cancels an operation. | [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) |
| Settings | Keep task-specific controls near the content they affect. Put infrequently changed app preferences in Settings, available through the standard app menu. | [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) |
| Numeric Entry | Use numeric formatting, validate input at an appropriate time, and give people enough information to correct invalid entries. | [Text Fields](https://developer.apple.com/design/human-interface-guidelines/text-fields) |
| Sliders | Label sliders, show live feedback where useful, and consider a text field or stepper when people need precise values. | [Sliders](https://developer.apple.com/design/human-interface-guidelines/sliders) |
| Windows | Adapt to window resizing and multitasking. Apple also cautions against placing critical actions only in a bottom bar. | [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) |
| Progress | Keep progress reporting accurate, provide feedback during work, and allow cancellation when it is safe. | [Progress Indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) |
| Accessibility | Label content for VoiceOver, provide keyboard and gesture alternatives, avoid color-only status, support larger text, and respect Reduce Motion. | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) |

## Findings and Implemented Changes

### Numeric Input and Saved Defaults

The original numeric text fields wrote directly to conversion settings. Output Scale's text field could bypass the adjacent stepper's range, and invalid default values could be saved immediately. Conversion then reported a general invalid-settings error without identifying the field.

`ValidatedNumberField`, `ValidatedScaleField`, `NumericInputDraft`, and `NumericInputRule` now keep an editable draft separate from the applied value. Return or leaving the field attempts a commit. Invalid input stays visible with a field-specific message; the last valid setting remains applied. Output Scale requires a whole number from one through ten thousand. Dimension and calibration fields require a finite number greater than zero.

Parsing considers the current locale and rejects incomplete or trailing text. Merely focusing and leaving a field does not round its stored precision. Tiny positive values use scientific notation when ordinary display formatting would show zero. Context changes synchronize the draft so an edit for one icon is not applied to another.

`ConversionOptionValidation` also checks saved defaults. `AppModel` preserves the last valid saved defaults when an update is invalid, reports the field involved, and uses a valid fallback when stored preferences cannot be used. This protects the model in addition to validating the visible fields.

### Commands, Cancellation, and Export Actions

`TubelineApp` now lists Fit Model, Front View, Reset View, and discrete orbit actions in the View menu. Camera requests use shared state so menu items and preview controls reach the same displayed camera. Export All's Command-E shortcut is defined in the menu rather than only on the footer button.

Cancel Export is available through Command-period in the Icons menu and Escape through the visible cancel button. Remove Selected Icon is also listed in the menu. `FileList` handles Delete only within the list's responder context, using the existing removal behavior; it does not install a global Delete shortcut that could interfere with numeric text editing.

The batch export remains the single prominent action and includes the icon count in its title. When there is only one icon, the redundant Export Selected footer button is hidden. Apple does not require selected-item export to become primary whenever an icon is selected; that remains a workflow choice. The current labels distinguish the batch action from selected-item export.

The footer remains the main visible export area. Menu access provides an additional route to export and cancellation, but the footer's destination and progress layout still need native review at small window sizes. Its placement is a deliberate design tradeoff against Apple's caution about critical bottom-bar actions.

### Window Size and Status

The main window minimum changed from 1,080 × 680 pt to 940 × 560 pt, and the sidebar minimum decreased to 200 pt. The destination button has a bounded width so a long folder name cannot take unlimited space from export controls. These changes permit narrower layouts in source; they do not establish that every control remains usable at the minimum size.

Export progress continues to report completed items rather than pretending to measure elapsed meshing time. Cancellation keeps completed files. Preview errors offer Try Again, and failed exports can be retried. Those paths need keyboard and assistive-technology verification in the running app.

### Accessible Rows and Preview

`JobRow` now identifies the source folder in its accessibility label and exposes the full source path as its value. Exported and failed states remain explicit alongside triangle counts, warnings, and custom-settings information. Tooltips include both source and export paths when available. The source-folder subtitle uses the secondary foreground style and caption size.

`ModelPreview` exposes a named accessibility image with a material-state description. Preview status distinguishes unavailable content from work in progress. Discrete orbit commands provide an alternative to dragging, and the preview responds to Reduce Motion by disabling camera inertia and stopping existing inertia. Source changes establish the intended behavior; VoiceOver announcements, keyboard operation, and motion behavior still require native checks.

The native sliders retain their labels and formatted accessibility values. No custom arrow-key handler was added merely because keyboard behavior had not been tested. Native slider focus and increments must be checked with Full Keyboard Access enabled.

## Verification Status

| Evidence | Status and Limit |
| --- | --- |
| Official guidance and implementation review | Completed against the Apple sources above and the current working-tree files. This establishes the source-level changes described here. |
| Focused numeric and model validation tests | Nineteen tests passed in the focused implementation run. This does not verify field focus, screen-reader announcements, or native rendering. |
| Integrated app tests | Passed sixty-nine tests with zero failures after the integrated changes, including numeric validation and camera orbit/Front regressions. Log: `/tmp/tubeline-hig-audit-tests.log`. |
| Native UI checks | The development app opened an original heart SVG and displayed 8,038 triangles. Invalid zero and empty scale edits showed correction guidance; correcting to 1 restored a valid field. View menu orbit changed the rendered angle, Command-1 restored the symmetric front silhouette, and Command-E exported with a completion summary and Finder action. Text deletion left the icon in the list. Saved defaults were unchanged. |
| Native accessibility and layout acceptance | Partial only. Accessibility-tree inspection confirmed source-folder/path labels and explicit exported status. No actual VoiceOver, Full Keyboard Access, contrast, enlarged-text, minimum-window-size, or Reduce Motion acceptance is claimed. |

## Remaining Native Checks

| Check | Required Observation |
| --- | --- |
| VoiceOver | Distinguish two same-name icons by source folder and full path. Confirm pending, working, exported, outdated, failed, and canceled statuses; warnings and custom settings must remain meaningful. Check the preview's unavailable, building, material, and error descriptions. |
| Full Keyboard Access | Add SVGs without dragging; reach Batch and Selected Icon settings; operate sliders and numeric fields; invoke export, cancel, retry, Finder reveal, and camera commands. Delete must remove a list selection while Delete in a text field edits text. |
| Numeric Correction | Enter zero, a negative value, a fraction for Output Scale, an out-of-range scale, incomplete exponents, and trailing text. Confirm the field explains the problem, preserves the last applied value, and accepts a correction. Check localized decimal input and switching icons with an unfinished draft. |
| Increased Contrast | Read source-folder subtitles, secondary help, unavailable controls, warning disclosures, and export errors. Verify each status remains distinguishable by text or symbol rather than color alone. |
| Larger Text | Enlarge text using the available macOS accessibility facilities. Check numeric guidance, error messages, scope descriptions, settings scrolling, and export controls at the minimum window size. Record any clipping or inaccessible content. |
| Light and Dark Appearance | Check native control contrast, material overlays, preview errors, and footer actions in both appearances. The preview background is intentionally dark, so inspect the transition to surrounding native controls. |
| Reduce Motion | Enable Reduce Motion before launch and while the preview is open. Confirm camera inertia stops, orbit commands remain usable, and no automatic camera movement continues after interaction. |
| Resizing and Long Content | Resize to 940 × 560 pt with a long source name, a long destination path, visible warnings, and an export error. Verify that export, cancellation, folder selection, and recovery remain reachable. |

Record the tested macOS version, display configuration, accessibility settings, and observed limitations when completing these checks. The native checks used the development Mac’s current dark appearance; changing global accessibility settings was outside this run. Attempts to resize through the automation surface did not establish the minimum-size layout, so that check remains open.
