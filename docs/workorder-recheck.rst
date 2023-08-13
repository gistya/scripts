workorder-recheck
=================

.. dfhack-tool::
    :summary: Recheck start conditions for a manager workorder.
    :tags: fort workorders

Sets the status to ``Checking`` (from ``Active``) of the selected work order.
This makes the manager reevaluate its conditions. This is especially useful
for an order that had its conditions met when it was started, but the requisite
items have since disappeared and the workorder is now generating job cancellation
spam.

Usage
-----

::

    workorder-recheck
