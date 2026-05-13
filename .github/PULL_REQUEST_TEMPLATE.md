<!-- New plugin submission or version bump -->

## Plugin

- **id:** `<your-plugin-id>` (must match the directory name)
- **Version:** `X.Y.Z`
- **Source URL:** `https://...`

## Submission checklist

- [ ] My `.zip` is hosted at an HTTPS URL with a valid certificate
- [ ] The archive's `plugin.lua` declares the same `id` as my manifest
- [ ] I computed the sha256 with `shasum -a 256` (or `Get-FileHash`) and pasted the lowercase hex
- [ ] I ran `python tools/validate.py` locally and it passed
- [ ] I tested the install end-to-end in cleat via **Install from URL...** before submitting

## Update PRs only

- [ ] I bumped `version` to match the new release tag
- [ ] I'm the same author / handle as the existing entry (or this is an authorized transfer — explain below)

## Notes for the reviewer

<!-- Anything unusual? Plugin permissions, ssh:exec patterns worth flagging,
     etc. Optional — feel free to delete this section. -->
