# Single-Image Prompt Template

Generate each image separately. Replace variables based on the article; do not combine multiple images into one.

## Pre-Generation Spec

For generation requests, prepare this compact spec before calling `image_gen`:

```text
#: {sequence number}
Placement: {where this belongs in the article}
Core idea: {one cognitive anchor}
Structure type: {one allowed structure type}
Xiaohei action: {what Xiaohei physically does}
Labels: {3-5 short English labels}
Save name: {NN-topic-slug.png}
```

The spec is a contract for generation. It is not a confirmation gate unless the user asked to approve the plan first.

## Image Prompt

```text
Generate one standalone 16:9 horizontal English article illustration.

Visual DNA:
Pure white background. Minimalist black hand-drawn line art. Slightly wobbly pen lines. Lots of empty white space. Sparse red/orange/blue handwritten English annotations. Clean absurd product-sketch feeling. No gradients, no shadows, no paper texture, no complex background, no commercial vector style, no PPT infographic look, no cute mascot poster, no children's illustration, no realistic UI.

Recurring IP character required:
Xiaohei, a small solid-black absurd creature with white dot eyes, tiny thin legs, blank serious expression, slightly uneven hand-drawn body shape. Xiaohei must perform the core conceptual action, not decorate the scene. Make Xiaohei serious, deadpan, and slightly bizarre, not cute.

Theme:
{article illustration theme}

Structure type:
{structure type: Workflow / system fragment / before-after contrast / character state / conceptual metaphor / layered method / route map / small comic sequence}

Core idea:
{core idea to express}

Composition:
{specific composition: where Xiaohei is, what Xiaohei is doing, the main object, and how information moves}

Suggested elements:
{element 1} / {element 2} / {element 3} / {element 4}

English handwritten labels:
{label 1} / {label 2} / {label 3} / {label 4} / {optional label 5}

Color use:
Black for main line art and Xiaohei. Orange for main flow/path/arrows. Red only for key warnings/problems/results. Blue only for secondary notes or feedback/system state.

Constraints:
One image explains only one core structure. Keep the main subject around 40%-60% of the canvas. Preserve at least 35% blank white space. Use at most 5-8 short handwritten English labels. Do not write a title in the top-left corner. Do not write the structure type on the image. Do not make it a formal diagram, course slide, or dense explainer. Do not copy prior examples or reuse known case compositions unless explicitly requested; invent a fresh visual metaphor for this specific article. It should be clear but not instructional, interesting but not childish, strange but clean. Do not use Chinese labels unless the user explicitly requests Chinese.
```

## Image Editing Prompt

Remove the top-left title:

```text
Edit the provided image. Remove only the handwritten title "{text to remove}" and its underline from the top-left corner. Fill that area with the same clean white background, matching the surrounding blank paper. Preserve everything else exactly: characters, labels, paths, line style, composition, aspect ratio, and image quality. Do not add any new text or objects.
```

## Increase Weirdness

```text
Regenerate this illustration with the same core meaning and simple layout, but make Xiaohei more central to the conceptual action. Xiaohei should be doing the strange work that explains the idea, not standing beside the diagram. Keep it clean, sparse, hand-drawn, and not cute.
```

## Save Handoff

After saving files locally, report:

```text
Generated {count} images.
QA:
| image | aspect ratio | white background | Xiaohei core action | labels | no title | no old-case reuse | saved path |
| {file name} | pass | pass | pass | pass, {count} short labels | pass | pass | {absolute path or not saved} |
Saved:
- {absolute/path/01-topic-name.png} - {purpose}
- {absolute/path/02-topic-name.png} - {purpose}
Most reliable: {image numbers}
Optional: {image numbers or "none"}
```

If generated images are not available as local files, say they were generated but not saved and name the destination folder that should receive them.
