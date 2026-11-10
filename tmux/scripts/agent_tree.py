#!/usr/bin/env python3
"""Refresh agent labels before tmux's choose-tree opens."""
import collections
import os
import subprocess
import sys
import time


def tmux(*args):
    return subprocess.run(['tmux', *args], text=True, capture_output=True)


def set_option(scope, target, name, value, cache):
    key = (scope, target, name)
    if cache is not None and cache.get(key) == value:
        return
    result = tmux('set-option', *([scope] if scope else []), '-q', '-t', target, name, value)
    if cache is not None and result.returncode == 0:
        cache[key] = value


def main(cache=None):
    listed = tmux('list-panes', '-a', '-F', '#{pane_id}\t#{window_id}\t#{session_id}')
    if listed.returncode:
        return 1
    rows = [line.split('\t') for line in listed.stdout.splitlines()]
    rows = [row for row in rows if len(row) == 3]
    try:
        scan = subprocess.run(
            [os.path.expanduser('~/.tmux/plugins/agenmux/target/release/agenmux'), 'list'],
            text=True, capture_output=True,
        )
    except OSError:
        scan = subprocess.CompletedProcess([], 1, '', '')
    states = {}
    labels = {'blocked': 'WAIT', 'working': 'WORK', 'idle': 'IDLE?', 'done': 'DONE'}
    if scan.returncode == 0:
        for line in scan.stdout.splitlines():
            fields = line.split('\t')
            if len(fields) >= 4:
                pane, _, agent, state = fields[:4]
                # Never insert arbitrary terminal output into a tmux format.
                agent = ''.join(c for c in agent if c.isalnum() or c in '-_')[:24]
                states[pane] = (labels.get(state, '?'), agent)
    pane_ids = {pane for pane, _, _ in rows}
    windows = collections.defaultdict(set)
    sessions = collections.defaultdict(set)
    for pane, window, session in rows:
        windows[window].add(pane)
        sessions[session].add(pane)
    palette = {'WAIT': '#f38ba8', 'WORK': '#f9e2af', 'DONE': '#a6e3a1', 'IDLE?': '#a6adc8', '?': '#fab387'}
    agent_colors = {'claude': '#fab387', 'codex': '#94e2d5', 'opencode': '#cba6f7'}

    def agent_badge(agent):
        color = agent_colors.get(agent.lower(), '#89b4fa')
        return f'#[fg={color},bold][{agent}]#[fg=default,nobold]'

    def badge(label, text):
        color = palette.get(label, '#fab387')
        # Blink only the work indicator; terminals may disable blinking.
        dot = f'#[fg={color},blink]●#[noblink]' if label == 'WORK' else f'#[fg={color}]●'
        return f'{dot} {text}#[fg=default,noblink]'

    for pane in pane_ids:
        state = states.get(pane)
        value = ""
        if state:
            label, agent = state
            value = badge(label, label) + " " + agent_badge(agent)
        set_option('-p', pane, '@am_tree_pane', value, cache)

    def summary(ids, show_agents=False):
        if scan.returncode:
            return '? scan unavailable'
        counts = collections.Counter(states[p][0] for p in ids if p in states)
        order = ('WAIT', 'WORK', 'DONE', 'IDLE?', '?')
        labels = [f'{name}:{counts[name]}' for name in order if counts[name]]
        plain = ' '.join(f'● {label}' for label in labels)
        # Compact unusually busy rows while preserving each count and color.
        short = {'WAIT': 'W', 'WORK': 'R', 'DONE': 'D', 'IDLE?': 'I?', '?': '?'}
        if show_agents and len(plain) > 21:
            labels = [f'{short[name]}:{counts[name]}' for name in order if counts[name]]
            status = ' '.join(badge(name, label) for name, label in zip((n for n in order if counts[n]), labels))
            plain = ' '.join(f'● {label}' for label in labels)
        else:
            status = ' '.join(badge(name, label) for name, label in zip((n for n in order if counts[n]), labels))
        agents = sorted({states[p][1] for p in ids if p in states and states[p][1]})
        if show_agents and agents:
            return status + ' ' * max(1, 22 - len(plain)) + '#[fg=#6c7086]│#[fg=default] ' + ' '.join(agent_badge(agent) for agent in agents)
        return status

    for window, ids in windows.items():
        set_option('-w', window, '@am_tree_window', summary(ids, show_agents=True), cache)
    for session, ids in sessions.items():
        set_option('', session, '@am_tree_session', summary(ids), cache)
    if scan.returncode:
        print('agenmux scan failed; tree still opens', file=sys.stderr)
    return 0


def watch(pane):
    mode = tmux('display-message', '-p', '-t', pane, '#{pane_mode}')
    if mode.returncode or mode.stdout.strip() != 'tree-mode':
        return 0
    token = os.urandom(12).hex()
    if tmux('set-option', '-pq', '-t', pane, '@am_tree_watch', token).returncode:
        return 1
    cache = {}
    while True:
        time.sleep(3)
        mode = tmux('display-message', '-p', '-t', pane, '#{pane_mode}\t#{@am_tree_watch}')
        if mode.returncode or mode.stdout.strip() != f'tree-mode\t{token}':
            return 0
        if main(cache):
            return 1
        # Setting options updates the mode on the next status-line refresh.
        # It does not inject keystrokes or change the selected tree item.


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--watch':
        sys.exit(watch(sys.argv[2]))
    sys.exit(main())
