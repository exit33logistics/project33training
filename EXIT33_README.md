# Exit #33 Logistics — Package
Generated: 2025-09-10T03:57:49.827196 UTC

Contents:
- exit33_full_build.html
- exit33_full_build_with_cert.html  (same content + front-end certificate generator)
- claude_master_prompt.txt
- EXIT33_README.md  (this file)
- exit33_package.zip

## Pre-flight checklist for engineers (copy before building)
- Color & brand:
  - Confirm exact hex codes to use: #ff0000 (red), #000000 (black), #ffffff (white).
  - Any other colors require approval.
- Content scope:
  - Reseller/license language must be omitted (user requested no resale/license text).
  - All module text in the HTML is final and must not be replaced with placeholders.
- Output format:
  - User requested a single inline HTML file. Confirm whether you should instead split assets.
- Certificate & data:
  - The included certificate generator is front-end only (client-side). Confirm if backend verification is required.
- Accessibility & compliance:
  - Add ARIA labels and keyboard navigation for interactive elements (nav dots are already present).
  - Confirm WCAG level target; adjust contrasts only if needed and keep palette exact.
- Hosting & fonts:
  - Confirm whether external fonts (Google Fonts) are allowed or stick to system fonts.
- Testing:
  - Which devices/resolutions should be prioritized for QA?
- Analytics & tracking:
  - Do not add analytics without approval.
- Delivery:
  - Preferred delivery format: single HTML (deliverable), or a repo/zip. This package is a ZIP.

## How to use
1. Upload `exit33_full_build.html` into Claude.ai along with the prompt in `claude_master_prompt.txt` if you want Claude to rebuild or produce a cleaned single-file output.
2. Or use `exit33_full_build_with_cert.html` to preview and generate printable certificates locally (client-side only).
3. The certificate tool opens a printable window and attempts to `window.print()` automatically (popups must be allowed). No backend is involved.

## Notes
- The certificate generator stores the last generated certificate in `sessionStorage` for convenience (only within the current browser session).
- If you need a server-backed certificate verification system, we can add an API design spec and minimal backend endpoints next.
