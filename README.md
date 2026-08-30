# BarebonesPDF

BarebonesPDF is a small native macOS Portable Document Format (PDF) reader and minor editor built with Swift, SwiftUI, Apple's PDFKit framework, and the free PDFium engine. It is designed for reading, annotation, page organization, metadata edits, limited existing-text rewrites, and straightforward exports without accounts, telemetry, or analytics.

The bundle identifier is `com.greenshoegarage.BarebonesPDF`. The app targets macOS 13 Ventura or newer and runs natively on Apple silicon and Intel Macs.

## What it does

- Opens PDFs from the Open dialog, Finder's **Open With** command, recent-document history, a window drop, or the Dock icon.
- Displays single-page or vertically continuous layouts with thumbnails, page navigation, Fit Page, Fit Width, Actual Size, and manual zoom.
- Selects and copies PDF text.
- Rewrites selected PDF text objects while retaining their size, color, transform, and placement. A matching standard PDF font is substituted when an embedded subset font cannot encode replacement characters reliably.
- Searches document text and moves between results.
- Prints through the standard macOS print panel and supports standard full-screen windows.
- Prompts for supported password-protected PDFs using PDFKit's local unlock API.
- Adds highlight, underline, strikethrough, ink, text box, sticky note, rectangle, oval, line, arrow, and signature-image stamp annotations.
- Selects, moves, restyles, edits, and removes annotations.
- Selects one or more thumbnails and reorders, rotates, duplicates, deletes, inserts, or extracts pages.
- Inserts pages from another PDF or creates a blank page matching the selected page size.
- Exports a selected page to Portable Network Graphics (PNG) or Joint Photographic Experts Group (JPEG) format at two-times PDF point resolution.
- Reads and edits title, author, subject, and keywords while showing useful read-only document details.
- Supports Undo and Redo for annotation and page mutations.

Every application control is connected to an implemented action. Commands are disabled when the active document or selection cannot use them.

## What “editing” does not mean

BarebonesPDF can rewrite the string stored by a basic existing PDF text object. It does **not** provide paragraph reflow, font substitution, OCR, or editing of outlined letters, photographs, paths, vector artwork, nested form objects, or every possible PDF text encoding. If PDFium cannot safely identify or encode a clicked object, the app refuses the edit and leaves the document unchanged.

PDFium is downloaded by Swift Package Manager at build time from the MIT-licensed `espresso3389/pdfium-xcframework` distribution. It is a free, open-source dependency; the app itself performs no network requests at runtime.

BarebonesPDF also is not a forms authoring tool, Optical Character Recognition (OCR) tool, redaction engine, certificate-signing product, PDF optimizer, or prepress application. It does not claim those capabilities.

## Requirements

- macOS 13 Ventura or newer
- Xcode 15 or newer
- A local Apple development identity only when signing, archiving, or installing outside Xcode

No package resolution, package manager, server, or network connection is required.

## Build and run

1. Unzip the project if necessary.
2. Open `BarebonesPDF.xcodeproj` in Xcode.
3. Select the **BarebonesPDF** scheme and **My Mac** as the run destination.
4. In the BarebonesPDF target's **Signing & Capabilities** tab, choose your development team if Xcode requests one. Keep **App Sandbox** enabled.
5. Press **Command-R**.

To run automated tests, choose **Product → Test** or press **Command-U**. The shared scheme contains the unit-test and user-interface-test targets.

Command-line builds on a Mac with Xcode installed:

```sh
xcodebuild \
  -project BarebonesPDF.xcodeproj \
  -scheme BarebonesPDF \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

Command-line tests:

```sh
xcodebuild \
  -project BarebonesPDF.xcodeproj \
  -scheme BarebonesPDF \
  -destination 'platform=macOS' \
  test
```

## Build in GitHub Actions

The repository includes `.github/workflows/build-macos.yml`. It compiles a universal Release build for Apple silicon and Intel on a GitHub-hosted macOS runner. No local Xcode installation or signing certificate is needed for this unsigned test build.

1. Create a GitHub repository and place the contents of this project at its root.
2. Push or upload the files to the repository's `main` branch.
3. Open the repository's **Actions** tab.
4. Select **Build BarebonesPDF**, then choose **Run workflow**.
5. When the run succeeds, download the `BarebonesPDF-macOS-unsigned` artifact from the run summary.
6. Unzip the artifact to obtain `BarebonesPDF.app`.

The workflow also runs for pushes and pull requests targeting `main`. If compilation fails, it uploads `BarebonesPDF-build-log` to make the error available without a Mac. The generated application is deliberately unsigned; public distribution still requires Apple Developer signing and notarization.

## Sandboxed file access

The App Sandbox is enabled. BarebonesPDF has only these additional entitlements:

- User-selected files: read/write
- Printing

There is no network client entitlement. Files selected in a native Open or Save panel are made available to the app by macOS. The document architecture retains access while that document is open. Inserting a PDF or choosing a signature image uses the security-scoped access supplied by the corresponding file panel and releases it immediately after reading.

Normal **Save**, **Save As**, **Duplicate**, versioning, conflict handling, and **Revert to Saved** behavior is provided by the native SwiftUI document system and `NSDocument` infrastructure. It performs coordinated writes and replaces the destination only after a new file representation has been prepared. Standalone exports use `SafeSaveService`, which requests Foundation's atomic write behavior: a temporary representation is completed before the destination is replaced.

## Release build

1. Select the BarebonesPDF target and assign an Apple Developer team.
2. Confirm the Release configuration still uses the `BarebonesPDF.entitlements` file.
3. Choose **Product → Archive**.
4. In Organizer, use **Distribute App** and choose the distribution route appropriate to your account.
5. For direct distribution outside the Mac App Store, use a Developer ID Application certificate, enable the hardened runtime, and complete Apple's notarization workflow.
6. For the Mac App Store, create the matching application identifier and listing in App Store Connect before uploading the archive.

Do not add a network entitlement unless the product scope is intentionally changed. BarebonesPDF does not need network access to function.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Command-O | Open |
| Command-S | Save |
| Shift-Command-S | Save As |
| Command-P | Print |
| Command-F | Search |
| Command-Z | Undo |
| Shift-Command-Z | Redo |
| Command-Plus | Zoom In |
| Command-Minus | Zoom Out |
| Command-0 | Actual Size |
| Command-1 | Fit Page |
| Command-2 | Fit Width |
| Command-Left Bracket | Previous Page |
| Command-Right Bracket | Next Page |
| Delete | Delete the selected annotation, otherwise selected pages |
| Option-Command-I | Document Information |

All primary commands also appear in the macOS menu bar. The standard document commands supplied by macOS remain available for new windows, Open Recent, close, duplicate, and revert.

## Annotation behavior

Choose the annotation button in the window toolbar to reveal the compact tool row. Choose **Edit Existing Text**, click a supported text object, enter its replacement, and save. This rewrites the content object and does not reflow surrounding text. Text markup tools operate on dragged text selections. Shape and ink tools use click-drag gestures. Text boxes, notes, and signature images are placed with a click. Select mode lets an annotation be selected and moved. The Properties inspector edits applicable annotation text, color, opacity, line width, font family, and font size.

Signature images are stored as custom PDF stamp annotations with the image bytes in a private annotation dictionary entry. They remain movable and reloadable in BarebonesPDF. PDFKit does not expose a standards-complete arbitrary image-stamp appearance API, so rendering or editability in third-party PDF software is not guaranteed. This feature is visual markup, not a cryptographic or legally validated digital signature.

## Page behavior

Use Command-click or Shift-click in the thumbnail list for multi-page selection. Drag the selected thumbnails to reorder them. Page operations create an in-memory recovery checkpoint before mutation and register it with the window's Undo manager. If an operation fails, the checkpoint is restored and the open document is kept intact.

Deleting a page is recoverable with Undo and therefore does not show an extra confirmation dialog. Export and extraction never remove pages from the source document.

## Known PDFKit limitations

- Saving through PDFKit rewrites a PDF representation. Unsupported or vendor-specific objects may be normalized or omitted even when visible page quality is preserved.
- Cryptographic signatures can become invalid after any document edit. BarebonesPDF does not re-sign PDFs.
- PDFKit can unlock many password-protected documents for viewing, but BarebonesPDF does not promise to preserve the original encryption policy after editing.
- Search and text selection depend on the PDF's embedded text layer. Image-only scans require external Optical Character Recognition (OCR), which is outside this project.
- Existing-text rewrites are limited to top-level text objects whose embedded font maps the requested Unicode characters. They retain the original styling and placement, do not reflow, and may overflow their original area. Scans, outlined text, and text nested in form objects are not editable.
- Very large PDF mutations may briefly consume additional memory because Undo checkpoints retain a complete pre-operation PDF representation. Progress is shown for page operations and exports, but PDFKit's serialization API does not expose byte-level progress.
- Page rotation is a saved page operation. PDFKit does not provide a separate, dependable view-only page-orientation transform on macOS.
- Free-text layout, annotation appearances, and blend behavior can differ between PDF viewers.
- Custom signature-image stamps have the portability caveat described above.
- Incremental PDF saves are not exposed by PDFKit. A save produces a new document representation.

If PDFKit cannot implement a feature reliably, BarebonesPDF leaves it out rather than showing a control that only looks functional.

## Project layout

```text
BarebonesPDF/
├── BarebonesPDF.xcodeproj/
├── BarebonesPDF/
│   ├── App/
│   ├── Document/
│   ├── Models/
│   ├── Services/
│   ├── Views/
│   ├── Assets.xcassets/
│   ├── BarebonesPDF.entitlements
│   └── Info.plist
├── BarebonesPDFTests/
├── BarebonesPDFUITests/
├── MANUAL_TEST_CHECKLIST.md
└── README.md
```

The architecture deliberately stays shallow. `DocumentState` coordinates the active PDFKit document and window state, while small services own page transformations, metadata, export rendering, and safe standalone writes.

## Privacy

All PDF parsing, rendering, annotation, searching, export, and saving happens locally. The project contains no analytics, telemetry, ads, accounts, subscriptions, remote services, third-party libraries, or network code.
