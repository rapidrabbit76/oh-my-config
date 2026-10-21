"""agent-notify: alerts from coding agents to Discord and ntfy.

Two class hierarchies, each with a registry:

- ``Agent`` (agents/): who an alert is from. Its profile, a name and an
  avatar, is what a channel shows, so alerts from different agents look like
  different senders. An agent whose CLI has hooks also reads them.
- ``Channel`` (channels/): where an alert goes.

A new agent is one subclass in agents/ with the ``@agent`` decorator; a new
channel is one subclass in channels/ with ``@channel``. Python 3.9 standard
library only.
"""

__version__ = "2.0.0"
