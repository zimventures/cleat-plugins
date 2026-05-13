<!-- New plugin submission or version bump -->

## Plugin

- **id:** `<your-plugin-id>` (must match the directory name and the `id` inside plugin.lua)
- **Version:** `X.Y.Z` (must match the `version` inside plugin.lua)
- **Homepage:** `https://...` (optional)

## Submission checklist

- [ ] My entry lives at `plugins/<id>/` with both `plugin.lua` and `plugin.json`
- [ ] The `id` field in `plugin.json` matches the directory name and the `id` inside `plugin.lua`
- [ ] The `version` field in `plugin.json` matches the `version` inside `plugin.lua`
- [ ] I did **not** include `source_url` or `sha256` in `plugin.json` (CI generates those)
- [ ] I ran `python tools/validate.py` locally and it passed
- [ ] I tested the plugin end-to-end in cleat (via **Create New Plugin...** or **Install from URL...**) before submitting

## Update PRs only

- [ ] I bumped `version` in both `plugin.json` and `plugin.lua`
- [ ] I'm the same author / handle as the existing entry (or this is an authorized transfer — explain below)

## Notes for the reviewer

<!-- Anything unusual? Plugin permissions, ssh:exec patterns worth flagging,
     etc. Optional — feel free to delete this section. -->
