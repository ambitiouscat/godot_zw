extends Node

## Compatibility shell for one migration release.
##
## Older plugin versions persisted this script as a project Autoload. The
## current plugin removes that exact setting and saves project.godot. Keeping a
## no-op script prevents a load error on the first editor start, before the
## migration plugin itself can run.
