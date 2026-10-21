"""Neighbour guards: two modules in a row must never be the same.

The pick of every module (the shopfront template, the house door, the window
treatment) is hashed and compared with the module on its left; if they match the
pick is re-rolled.  The count of re-rolls is printed with the build, so the variety
is measured and not just claimed.
"""
import zlib


def digest(value):
    """A deterministic digest of a pick.

    Python's built-in hash() is salted per run, so the build would not be
    reproducible; crc32 of the repr is.
    """
    return zlib.crc32(repr(value).encode("utf-8"))


class NeighbourGuard(object):
    """Re-rolls a module's pick until it differs from the one on its left."""

    REROLLS = 0        # the total over the build (printed with the build log)

    def __init__(self):
        self.previous = {}      # salt -> the digest of the last pick of that module
        self.rerolls = 0
        self.count = 0

    def choose(self, picker, salt=""):
        """`picker()` returns the pick; it is re-rolled while it matches the left.

        Every module has its own slot: the shopfront, the fascia and the window
        treatment are three different rows of a shopfront, and none of them may
        repeat the module on its left.
        """
        pick = None
        key = None
        for _ in range(8):
            pick = picker()
            key = digest((salt, pick))
            if self.previous.get(salt) is None or key != self.previous[salt]:
                break
            self.rerolls += 1
            NeighbourGuard.REROLLS += 1
        self.previous[salt] = key
        self.count += 1
        return pick

    def note(self, value, salt=""):
        """Record a pick that was made somewhere else, so the next one differs."""
        self.previous[salt] = digest((salt, value))
        self.count += 1
