# Agent Note: adapter-owned effort slider in the model picker

Status: implemented

English | [中文](2026-08-14-effort-slider-in-model-picker.zh.md)

## Problem

The model picker already receives each exact model's adapter-owned reasoning levels, but a text list makes an ordered effort scale harder to scan and operate. The control must remain valid for providers that expose different identifiers or a different number of levels.

## Decision

The `@deepseek-ai/dsh-client-ui-model-selection` composer Effort pane renders the adapter-provided ordered choices as a discrete native range input with Faster and Smarter endpoints. The current effort is shown in the heading and `aria-valuetext`; the range is keyboard accessible and uses the adapter's order without interpreting effort ids.

The range change calls the existing per-session `session.selectModel` path with the unchanged provider/model pair and the selected opaque effort id. Provider-default remains an explicit first stop only when the model has no configured default, so omitting `reasoningEffort` continues to restore provider behavior.

Only the presentation changes. The model picker still owns no effort vocabulary, does not accept arbitrary ids, and persists an accepted selection through the existing Host/default-model path.

## Alternatives considered

**Keep the text-only effort list.** It preserves the protocol but does not provide the requested ordered effort affordance or the Faster-to-Smarter visual orientation.

**Hard-code `off`, `high`, and `max` slider stops.** Adapter-owned identifiers and counts differ across providers, so hard-coded stops would hide supported levels or send invalid ids.

**Add a separate client-side effort setting.** A second state owner could diverge from the Host-reported session selection and would bypass the existing validation and persistence path.

## Consequences

The composer presents one compact, keyboard-operable effort control and keeps all request, validation, persistence, and model-specific capability ownership in the existing Host and adapter seams. The endpoint labels describe visual order only; they do not claim that every provider's first or last id has a particular semantic name.

The keyless component test and declared-reasoning web scenario verify that the slider exposes the adapter's exact count/order and that changing it still records the selected effort.
