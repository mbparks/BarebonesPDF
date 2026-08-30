# BarebonesPDF Manual Test Checklist

This checklist covers the app's Portable Document Format (PDF) workflows.

Run this checklist on the oldest supported system, macOS 13, and on the newest available macOS release. Where hardware is available, test one Apple silicon Mac and one Intel Mac.

## Build and launch

- [ ] Open `BarebonesPDF.xcodeproj` without missing-file warnings.
- [ ] Build the BarebonesPDF scheme in Debug configuration.
- [ ] Build the BarebonesPDF scheme in Release configuration.
- [ ] Confirm the app has no third-party package-resolution step.
- [ ] Launch to the quiet welcome screen when window restoration has no prior document.
- [ ] Confirm **Open PDF** opens the native file panel.
- [ ] Confirm **Create Blank PDF** creates one letter-size blank page.
- [ ] Quit with a PDF window open, relaunch, and verify normal macOS window restoration behavior.

## Open and protected files

- [ ] Open a PDF with Command-O.
- [ ] Open the same PDF from Finder with **Open With → BarebonesPDF**.
- [ ] Drag a PDF onto the welcome window.
- [ ] Drag a PDF onto the app icon in the Dock.
- [ ] Confirm the file appears under **File → Open Recent**.
- [ ] Open a supported password-protected PDF, enter a wrong password, and verify a clear error.
- [ ] Enter the correct password and verify pages display.
- [ ] Open a malformed non-PDF file renamed with a `.pdf` extension and verify a nontechnical error.

## Reading and navigation

- [ ] Scroll a multi-page PDF in Continuous mode.
- [ ] Switch to Single Page mode and navigate with the toolbar.
- [ ] Use Command-Left Bracket and Command-Right Bracket.
- [ ] Enter the first, middle, and last page numbers in the page field.
- [ ] Test Fit Page, Fit Width, Actual Size, Zoom In, and Zoom Out.
- [ ] Resize the window and verify the central canvas remains usable.
- [ ] Hide and restore the thumbnail sidebar.
- [ ] Enter and leave full screen.
- [ ] Select text and copy it to another application.
- [ ] Print to the system PDF preview from the native print panel.

## Search

- [ ] Open search with Command-F.
- [ ] Search for a term with multiple results.
- [ ] Move through results with both arrow buttons and Command-G shortcuts.
- [ ] Search for a missing term and verify **No results**.
- [ ] Close search and verify highlights are cleared.

## Annotations

- [ ] Add a highlight, underline, and strikethrough to selected text.
- [ ] Add a freehand drawing.
- [ ] Add a text box and change its text, font family, font size, and color.
- [ ] Add a sticky note and edit its contents.
- [ ] Add a rectangle, oval, line, and arrow.
- [ ] Choose a local Portable Network Graphics (PNG) or Joint Photographic Experts Group (JPEG) signature image and place it on a page.
- [ ] Select and move each annotation type.
- [ ] Change applicable opacity, line width, and color properties.
- [ ] Delete an annotation with the toolbar eraser.
- [ ] Delete a selected annotation with the Delete key.
- [ ] Undo and Redo annotation creation, movement, property changes, and deletion.
- [ ] Save, close, and reopen; verify ordinary annotations remain and are editable.
- [ ] Reopen in BarebonesPDF and verify a signature image remains visible, movable, and editable.
- [ ] Open the saved file in Preview and record the signature-stamp interoperability result.

## Pages

- [ ] Command-click several nonadjacent thumbnails and verify multi-selection.
- [ ] Shift-click a contiguous page range.
- [ ] Drag selected thumbnails to the beginning, middle, and end of the document.
- [ ] Rotate selected pages left and right.
- [ ] Duplicate one page and a multi-page selection.
- [ ] Insert all pages from another readable PDF.
- [ ] Attempt to insert a locked PDF and verify a clear error without changing the open document.
- [ ] Insert a blank page and verify it matches the selected page's dimensions.
- [ ] Delete selected pages and recover them with Undo.
- [ ] Undo and Redo every page operation.
- [ ] Extract selected pages to a new PDF and verify source pages remain.
- [ ] Export a page to PNG and JPEG and verify the dimensions and orientation.

## Metadata and saving

- [ ] Open Document Information with Option-Command-I.
- [ ] Edit title, author, subject, and comma-separated keywords.
- [ ] Verify file name, size, page count, first-page dimensions, version, dates, and security status.
- [ ] Apply metadata, save, close, reopen, and verify values persist.
- [ ] Verify the status bar indicates an edited document after a mutation.
- [ ] Save with Command-S.
- [ ] Use Shift-Command-S for Save As and verify the original remains unchanged.
- [ ] Use the native Duplicate command and verify the original remains unchanged.
- [ ] Revert a saved change with **Revert to Saved**.
- [ ] Simulate an export failure with an unwritable destination and verify the original remains readable and open work remains present.
- [ ] Close a modified document and verify standard macOS save-review behavior.

## Accessibility and appearance

- [ ] Navigate the toolbar, thumbnail list, canvas, inspector, search, and metadata sheet using only the keyboard.
- [ ] Use VoiceOver to inspect every interactive control and verify useful labels.
- [ ] Verify selected tools expose selected state without relying only on color.
- [ ] Test Light Mode and Dark Mode.
- [ ] Change the system accent color and verify controls follow it.
- [ ] Enable Increase Contrast and verify boundaries and state remain clear.
- [ ] Enable Reduce Motion and verify no essential information depends on animation.
- [ ] Increase the display scaling and confirm labels do not clip in the main workflows.

## Large-document and regression pass

- [ ] Open a PDF over 500 pages and verify a progress cursor or visible state appears for lengthy work.
- [ ] Scroll quickly through thumbnails and pages without a crash.
- [ ] Search the large file and verify the app remains responsive after the result set arrives.
- [ ] Perform one page operation, one annotation edit, Save As, close, and reopen.
- [ ] Run Product → Test and verify both unit-test and user-interface-test targets pass on the test Mac.
