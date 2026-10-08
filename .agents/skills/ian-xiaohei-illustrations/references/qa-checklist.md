# QA Checklist

## Must-Pass Items

- 16:9 horizontal.
- Clean white background.
- Has Xiaohei.
- Xiaohei performs the core action and is not just decoration.
- No old-case reuse; it should be a new metaphor for the current article.
- Weird, creative, and interesting.
- Clean and spacious; the subject should not take more than about 60% of the frame.
- One image should explain only one core structure.
- English labels are sparse, short, and readable.
- Orange is used only for the main path or arrow.
- Red is used only for key notes, problems, reminders, or results.
- Blue is used only for side notes, feedback, or system state.
- Generation requests have one compact spec per image before `image_gen` is called, when the host allows a short text response.
- The final handoff includes a compact QA manifest for every generated or edited image.
- Saved deliverables use slugged sequential PNG names and do not overwrite existing files unless replacement was requested.
- The final handoff includes absolute filesystem paths for every saved file.

## Failure Signals

If any of the following appear, regenerate or edit locally:

- A top-left title such as "Common Pitfalls", "Workflow", "System Architecture", or "Route Map".
- Xiaohei looks like a mascot, meme, or cute cartoon.
- The image looks like a PPT, course slide, or formal flowchart.
- Too many elements, arrows, or nodes.
- The text becomes long-form explanation.
- The background has paper texture, shadows, gradients, beige color, or noise.
- There is a real UI screenshot or tech-interface look.
- English spelling mistakes are severe or labels are unreadable.
- The image feels stiff and has no absurd metaphor.
- It looks too similar to the old examples in `assets/examples/`.
- The agent combines multiple requested images into one grid or collage.
- The generated file is handed off without a saved path when the user expected workspace files.
- A destination asset is overwritten without explicit replacement permission.

## Iteration Methods

- Too ordinary: make Xiaohei the action subject and add a weird but coherent metaphor.
- Too complex: remove nodes and keep one action and 3-5 short labels.
- Too cute: emphasize deadpan, blank serious expression, not cute, not mascot.
- Too PPT-like: remove titles, borders, clean grids, and too many arrows. Make it feel like a hand-drawn scene.
- Too similar to an old example: keep the core meaning, but change the main object and Xiaohei's action.
- Text is wrong: edit locally first; if there are too many errors, regenerate and reduce the number of labels.
- Save path conflict: keep the original file and append `-v2`, `-v3`, and so on.

## QA Manifest

Before final handoff, list one row per generated or edited image:

```text
| image | aspect ratio | white background | Xiaohei core action | labels | no title | no old-case reuse | saved path |
| 01-topic-name.png | pass | pass | pass | pass, 4 short labels | pass | pass | /absolute/path/01-topic-name.png |
```

Use `not saved` in the saved path column only when the host produced an image attachment without a local file path. If any column is not `pass`, state the fix taken or mark the image as optional.

## Delivery Check

A high-quality image should make the reader first think, "This is a little weird," and then understand the structure within one second.

If it first looks like a tutorial page rather than a weird product sketch on white paper, it is not good enough.

The handoff is not complete until the user can inspect the saved PNG paths or understands that the host did not expose local generated files.
