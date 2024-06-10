adv-rumors
==========

.. dfhack-tool::
    :summary: Improves the conversation menus in Adventure mode.
    :tags: adventure interface

When you start a conversation with someone in adventure mode, this tool will:

- Make conversation topics searchable by additional useful keywords based on the topic description
- Add ``slay`` and ``kill`` keywords for topics about someone who was slain

Overlay
-------

This script functions via an overlay that is managed by the `gui/overlay` framework.
When the ``adv-rumors.conversation`` overlay is enabled, the script will
automatically run on the convesration screen,
introducing additional keywords.
