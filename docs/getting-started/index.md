# Getting started

If you're new to cleat plugins, work through these two pages in order:

1. **[Quickstart](quickstart.md)** — write your first plugin in 10
   minutes using cleat's built-in Create New Plugin wizard. End-to-end:
   pick a template, edit it, watch it run against a real connection,
   then submit it to the registry.
2. **[Plugin lifecycle](lifecycle.md)** — how cleat schedules and runs
   your plugin. Covers the `collect → transform → render` flow, polling
   vs streaming, the four `data_type` values, and where each runs in
   cleat's threading model.

Once you've got a plugin running, drill into the
[**Lua API reference**](../api/index.md) for the full surface of host
calls, widget primitives, and data-store queries available to your
code.
