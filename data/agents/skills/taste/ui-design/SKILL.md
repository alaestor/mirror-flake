---
name: ui-design
description: Principles for designing clear, efficient user interfaces with low interaction cost and appropriate complexity.
---

# UI design principles

Design interfaces that communicate through layout and behavior rather than excessive explanation. Minimize cognitive load and interaction cost without limiting functionality.

Apply these principles with judgment. User expectations, accessibility, and the task itself take precedence over rigid rules.

## 1. Communicate through structure

Use spatial relationships to convey meaning.

- Group related elements through proximity, alignment, and containment.
- Place controls near the elements they affect.
- Use spacing, typography, and visual hierarchy to distinguish roles and relationships.
- Prefer contextual controls over detached toolbars when practical.
- Remove labels and explanations that merely repeat what the layout already communicates.

For example, two media players with their own adjacent playback controls need no text explaining which buttons belong to which player.

Relevant concepts: Gestalt principles, proximity, visual hierarchy, direct manipulation.

## 2. Optimize for interaction frequency

The expected frequency of an interaction should strongly influence its visibility and cost.

- Keep frequently used actions immediately accessible.
- Place occasional actions in contextual menus or secondary controls.
- Reserve deeper navigation and settings dialogs for infrequent operations.
- Evaluate frequency within the relevant workflow, not just across the application.
- Consider experienced users when estimating frequency. Advanced functionality is not necessarily infrequently used.
- Minimize repeated effort. An extra click on an action performed hundreds of times matters more than several clicks on an annual setting.

Use interaction frequency as a guide:

| Frequency | Preferred access |
|-----------|------------------|
| Constant | Immediate access, minimal effort, intuitive shortcuts |
| Frequent | Visible contextual controls, optional shortcuts |
| Occasional | Menus, secondary controls, expandable sections |
| Rare | Settings, dialogs, deeper navigation |

Frequency is not the only consideration. Urgency, safety, discoverability, and available screen space also affect placement.

Relevant concepts: Progressive disclosure, interaction cost, frequency of use, keystroke-level model, Fitts's law.

## 3. Prefer concise controls

Use visual controls when they communicate more efficiently than text.

- Prefer familiar icon buttons for common actions, especially in compact or repetitive interfaces.
- Use tooltips for clarification, shortcuts, and secondary hints.
- Avoid explanatory subheadings and instructions when the interface is already clear.
- Use visible labels when icons are ambiguous or unfamiliar.
- Keep icon meanings and interaction conventions consistent.

Do not sacrifice clarity to reduce text. An ambiguous icon is worse than a labeled button, but the user can learn from tooltips. Label buttons can still be useful for significant operations (e.g. you don't want icons for an execute/abort dialogue).

Relevant concepts: Recognition over recall, discoverability, affordances.

## 4. Support different levels of expertise

Make common workflows accessible to newcomers without slowing down experienced users.

- Provide obvious GUI controls for primary actions.
- Offer keyboard shortcuts and other accelerators for repeated operations.
- Give extremely frequent actions intuitive shortcuts that casual users can learn easily.
- Make less common shortcuts discoverable through tooltips and menus.
- Avoid forcing experienced users through repeated dialogs or nested navigation.
- Do not require users to memorize shortcuts to perform essential tasks.

Prefer layered interaction. The basic workflow should be obvious, while advanced functionality remains accessible without cluttering the interface.

We want to enable power-users without alienating or overloading newbies. Make speedups discoverable but not mandatory, like listing a key-combo shortcut under the explainer in a tooltip. Having multiple "modes" in your interface can be useful when complexity is unavoidable; e.g. a "simplified" / "advanced" toggle for some flow or portion of the interface. Hiding power-user complexity between a settings menu toggle may also be a fine approach, especially if the complexity increase is app-wide. We would ideally prefer to avoid having multiple modes / duplication of surfaces, but sometimes it can be the right approach.

Relevant concepts: Expert accelerators, flexibility and efficiency of use, progressive complexity.

## 5. Handle destructive actions safely

Protect users against accidental destructive operations without introducing unnecessary friction.

- Confirm consequential or irreversible destructive actions.
- State what the operation will affect.
- Prefer undo over confirmation for easily reversible operations.
- Avoid repeated confirmations for routine, low-risk actions.
- Allow appropriate modifier-based shortcuts for experienced users.
- Holding Shift (or another designated modifier) may expose additional context-menu actions, reveal shortcuts on hover, or bypass eligible confirmations.
- Do not bypass safeguards for irreversible or unusually consequential operations.

For confirmation of destructive operations that are very infrequent and have significant blast radii, especially in a pop-up or interaction-heavy flow: prefer hover-time gates on the destructive action button. The button may appear disabled initially, and the user must hover for some period of time before it becomes active (ideally with feedback in the form of color or animation). This is "extreme" and should be used very sparingly (e.g. to confirm deletion of account, toggling a dangerous mode, disabling critical safeguards, etc). This design doesn't make sense in a buried menu where the user is actively looking for the button: it is intended to prevent impulsive or reactionary interaction (the antithesis of a dark-pattern confirmation flow).

Relevant concepts: Error prevention, reversibility, safe defaults.

## 6. Control information density

Display information according to its relevance to the current task.

- Prioritize information users need to make their next decision.
- Hide secondary details until they become relevant or the user requests them.
- Remove redundant labels, decorations, and controls.
- Use whitespace to separate meaningful groups rather than spreading elements arbitrarily.
- Keep important state and feedback visible.
- Avoid excessive minimalism that makes functionality difficult to find.

A compact interface can be clear, and a spacious interface can be confusing. Optimize the organization of information rather than its quantity alone.

Relevant concepts: Cognitive load, information density, visual hierarchy, signal-to-noise ratio, alarm fatigue.

## 7. Preserve discoverability and feedback

Users should understand what actions are available and what happened after performing them.

- Make primary actions recognizable.
- Follow established interaction conventions unless there is a concrete reason to depart from them.
- Provide clear hover, focus, active, disabled, loading, and error states.
- Show the results of actions near the affected elements when practical.
- Use tooltips to supplement a clear interface, not compensate for a confusing one.
- Support keyboard navigation, touch input, and assistive technologies.
- Do not make essential information or actions available exclusively through hover or modifier keys.

Relevant concepts: Visibility of system status, feedback, consistency, accessibility.

## Review criteria

When designing or reviewing an interface, check:

1. Does the layout communicate relationships without unnecessary text?
2. Are frequently used actions accessible with minimal effort?
3. Does the interface hide infrequent controls without burying important functionality?
4. Can newcomers discover the primary workflow without instruction?
5. Can experienced users perform repeated operations efficiently?
6. Are icons recognizable, with labels or tooltips where needed?
7. Are destructive actions protected according to their consequences?
8. Does the interface clearly communicate its current state and the results of user actions?
9. Does each visible element provide useful information or functionality?

When principles conflict, favor clarity, predictability, accessibility, and cumulative task efficiency over visual minimalism.
