"""commit-msg hook: enforce this repo's Conventional Commits rules.

Runs at the `commit-msg` git stage (see `.pre-commit-config.yaml`) and again
in CI (`.github/workflows/ci.yml`) over each pushed or PR commit, so
`check()` is pure (no file I/O) and both callers share it through `main()`.

Rules and rule numbers follow
https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13 plus this
repo's own rules: subject 50, body 72, and no AI attribution (rule 9).
"""

import re
import sys
from pathlib import Path

VALID_TYPES = {
    "feat",
    "fix",
    "refactor",
    "perf",
    "style",
    "test",
    "docs",
    "build",
    "ops",
    "chore",
}

# Curated, not exhaustive. Matched on the first word of the description
# only: "test: add fixes for the pager" must pass, because "fixes" is not
# the first word.
NON_IMPERATIVE_FIRST_WORDS = {
    "added",
    "adds",
    "adding",
    "fixed",
    "fixes",
    "fixing",
    "updated",
    "updates",
    "updating",
    "changed",
    "changes",
    "changing",
    "removed",
    "removes",
    "removing",
    "refactored",
    "refactors",
    "created",
    "creates",
    "bumped",
    "bumps",
}

SUBJECT_MAX = 50
BODY_MAX = 72

# type(scope)!: description, with scope and ! both optional. Type is matched
# loosely here (any letters) so an unknown type is reported as rule 2
# ("wrong type"), not rule 1 ("wrong grammar").
SUBJECT_RE = re.compile(
    r"^(?P<type>[A-Za-z]+)(\((?P<scope>[^()]*)\))?(?P<bang>!)?: (?P<desc>.+)$"
)

# Subjects exempt from every rule below, matched on the raw subject line.
# Merge/revert keep git's own formats; fixup!/squash! are rebase
# placeholders.
EXEMPT_PREFIXES = (
    "Merge ",
    'Revert "',
    "fixup!",
    "squash!",
)

# Agents don't sign commits here: the author line is the owner's, and a
# model trailer on every commit is noise in `git log`. Claude Code's
# `attribution` setting turns these off, but it has been ignored in some
# releases, so this check is the backstop.
ATTRIBUTION_RE = re.compile(
    r"^(co-authored-by:.*(claude|anthropic|noreply@anthropic\.com)"
    r"|claude-session:"
    r"|.*generated with \[?claude code)",
    re.IGNORECASE,
)

# Git's verbose-mode diff starts below the scissors line.
SCISSORS_RE = re.compile(r"^# -+ >8 -+")


def _content_lines(message: str) -> list[str]:
    """Strip git's comment block and verbose diff, return real message lines."""
    lines = message.splitlines()
    for i, line in enumerate(lines):
        if SCISSORS_RE.match(line):
            lines = lines[:i]
            break
    lines = [line for line in lines if not line.startswith("#")]
    # Git leaves a blank line before the comment block it appends; that's
    # formatting, not body content. Compared with .strip() so a
    # whitespace-only line doesn't survive as a fake subject.
    while lines and lines[-1].strip() == "":
        lines.pop()
    return lines


def _fenced_line_indices(lines: list[str]) -> set[int]:
    """Indices of lines inside a ``` fenced block, delimiters included."""
    fenced = set()
    in_fence = False
    for i, line in enumerate(lines):
        if line.startswith("```"):
            fenced.add(i)
            in_fence = not in_fence
            continue
        if in_fence:
            fenced.add(i)
    return fenced


def check(message: str) -> list[str]:
    """Return one human-readable complaint per broken rule; empty list = ok."""
    lines = _content_lines(message)
    if not lines:
        return []  # empty or comment-only message; git aborts this itself

    subject = lines[0]
    if subject.startswith(EXEMPT_PREFIXES):
        return []

    complaints: list[str] = []
    match = SUBJECT_RE.match(subject)

    if match is None:
        complaints.append(
            "rule 1: subject must match "
            f"'<type>(<scope>)?!?: <description>': {subject!r}"
        )
    else:
        commit_type = match.group("type")
        desc = match.group("desc")

        if commit_type not in VALID_TYPES:
            complaints.append(
                f"rule 2: type {commit_type!r} is not one of "
                f"{sorted(VALID_TYPES)}: {subject!r}"
            )

        if desc[:1].isascii() and desc[:1].isupper():
            complaints.append(
                "rule 4: description must not start with an "
                f"uppercase letter: {subject!r}"
            )

        words = desc.split(maxsplit=1)
        first_word = words[0].strip(".,;:!?").lower() if words else ""
        if first_word in NON_IMPERATIVE_FIRST_WORDS:
            complaints.append(
                f"rule 6: description starts with non-imperative {first_word!r}, "
                f"use the imperative mood: {subject!r}"
            )

    if len(subject) > SUBJECT_MAX:
        complaints.append(
            f"rule 3: subject exceeds {SUBJECT_MAX} characters "
            f"(got {len(subject)}): {subject!r}"
        )

    if subject.endswith("."):
        complaints.append(f"rule 5: subject must not end with a period: {subject!r}")

    body = lines[1:]
    if body:
        if body[0] != "":
            complaints.append(
                f"rule 7: line 2 must be blank when a body is present: {body[0]!r}"
            )

        fenced = _fenced_line_indices(body)
        for i, line in enumerate(body):
            if i == 0 and body[0] == "":
                continue
            if len(line) <= BODY_MAX:
                continue
            if " " not in line and "\t" not in line:
                continue  # unbreakable token, e.g. a URL
            if i in fenced:
                continue
            # Numbered against the whole message as the author sees it in
            # their editor: body[i] is message line i + 2 (1-based).
            complaints.append(
                f"rule 8: line {i + 2} exceeds {BODY_MAX} characters "
                f"(got {len(line)}): {line!r}"
            )

    for line in body:
        if ATTRIBUTION_RE.match(line.strip()):
            complaints.append(
                f"rule 9: no AI attribution trailers or footers: {line!r}"
            )

    return complaints


def main(argv: list[str] | None = None) -> int:
    """Read the commit message file at argv[1], print complaints, return 1 if any."""
    argv = sys.argv if argv is None else argv
    message = Path(argv[1]).read_text()
    complaints = check(message)
    for complaint in complaints:
        # stdout is this script's interface: git shows it to the committer
        # and CI prints it to the log.
        print(complaint)  # noqa: T201
    return 1 if complaints else 0


if __name__ == "__main__":
    raise SystemExit(main())
