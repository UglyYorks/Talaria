# Notch Overlay

- When the user moves the cursor to the top center of the screen, the app must show the notch overlay.
- While the user is dragging file(s), the large drop prompt must only appear after the user shakes the cursor during that active file drag.
- Dragging file(s) alone must not show the large drop prompt.
- After the large drop prompt appears, it must show a small progress line at the bottom for 10 seconds, then hide until the user shakes the cursor again during the active file drag.
- The progress line must have a darker grey track and a lighter grey fill that advances from left to right.
- Hovering the cursor over the notch must pause the large drop prompt timeout and progress line.
- When files are not hovering over the notch, the large drop prompt must say "Drop file here" for one detected file and "Drop files here" for multiple or unknown file counts.
- While files hover over the notch, hide the progress line and label. Show a rectangle with a dashed, semi-transparent border and a large drop icon that fades in and slides down from above over 200 ms. Restore the prompt when files leave.
