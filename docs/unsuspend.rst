unsuspend
=========

.. dfhack-tool::
    :summary: Unsuspends building construction jobs.
    :tags: fort productivity jobs

Unsuspends building construction jobs, except for jobs managed by `buildingplan`
and those where water flow is greater than 1. This allows you to quickly recover
if a bunch of jobs were suspended due to the workers getting scared off by
wildlife or items temporarily blocking building sites.

See `suspendmanager` in `gui/control-panel` to automatically suspend and
unsuspend jobs.

Usage
-----

::

    unsuspend

Options
-------

``-q``, ``--quiet``
    Disable text output

``-s``, ``--skipblocking``
    Don't unsuspend construction jobs that risk blocking other jobs

Overlay
-------

This script also provides an overlay that is managed by the `overlay` framework.
When the overlay is enabled, an icon or letter will appear over suspended
buildings:

- A clock icon (green ``P`` in ASCII mode) indicates that the building is still
  in planning mode and is waiting on materials. The `buildingplan` plugin will
  unsuspend it for you when those materials become available.
- A white ``x`` means that the building is maintained suspended by
  `suspendmanager`, selecting it will provide a reason for the suspension
- A yellow ``x`` means that the building is suspended. If you don't have
  `suspendmanager` managing suspensions for you, you can unsuspend it
  manually or with the `unsuspend` command.
- A red ``X`` means that the building has been re-suspended multiple times.
  You might need to look into whatever is preventing the building from being
  built (e.g. the building material for the building is inaccessible or there
  is an in-use item blocking the building site).

Note that in ASCII mode the letter will only appear when the game is paused
since it takes up the whole tile and makes the underlying building invisible.
In graphics mode, the icon only covers part of the building and so can always
be visible.
