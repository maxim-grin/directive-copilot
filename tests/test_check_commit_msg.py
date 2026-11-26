from pathlib import Path

import pytest

from tools.check_commit_msg import check, main


def rules(message: str) -> list[str]:
    return [c.split(":", 1)[0] for c in check(message)]


@pytest.mark.parametrize(
    "message",
    [
        "feat: add judge interface",
        "fix(grade): reject quotes missing from the chunk",
        "feat(api)!: rename the ask endpoint",
        "test: add fixes for the eval runner",  # "fixes" isn't the first word
        "ops(k8s): pin the pgvector image\n\nBody line.\n",
        "fix: pair on the judge\n\nCo-Authored-By: Sam Lee <sam@example.com>",
        "Merge branch 'main' into feat/jev-judge",
        'Revert "feat: add judge interface"',
        "fixup! feat: add judge interface",
        "",
        "# only a comment\n",
    ],
)
def test_valid_messages(message: str) -> None:
    assert check(message) == []


@pytest.mark.parametrize(
    ("message", "expected"),
    [
        ("add judge interface", ["rule 1"]),
        ("feature: add judge interface", ["rule 2"]),
        ("feat: Add judge interface", ["rule 4"]),
        ("feat: added judge interface", ["rule 6"]),
        ("feat: add a judge interface that can call either an LLM", ["rule 3"]),
        ("feat: add judge interface.", ["rule 5"]),
        ("feat: add judge interface\nno blank line", ["rule 7"]),
        ("feat: add judge\n\n" + "word " * 20, ["rule 8"]),
        (
            "feat: add judge\n\nCo-Authored-By: Claude <noreply@anthropic.com>",
            ["rule 9"],
        ),
        ("feat: add judge\n\nClaude-Session: https://claude.ai/code/x", ["rule 9"]),
        ("feat: add judge\n\n🤖 Generated with [Claude Code](https://x)", ["rule 9"]),
    ],
)
def test_invalid_messages(message: str, expected: list[str]) -> None:
    assert rules(message) == expected


def test_long_lines_allowed_for_urls_and_code_fences() -> None:
    url = "https://example.com/" + "a" * 80
    fenced = "```\n" + "x " * 50 + "\n```"
    assert check(f"docs: link the directive\n\n{url}\n\n{fenced}\n") == []


def test_git_comments_and_verbose_diff_are_ignored() -> None:
    message = (
        "feat: add judge interface\n\n"
        "# Please enter the commit message for your changes.\n"
        "# ------------------------ >8 ------------------------\n"
        "diff --git a/x b/x\n" + "y " * 60 + "\n"
    )
    assert check(message) == []


def test_main_exit_codes(tmp_path: Path) -> None:
    good, bad = tmp_path / "good", tmp_path / "bad"
    good.write_text("feat: add judge interface\n")
    bad.write_text("Added stuff.\n")
    assert main(["prog", str(good)]) == 0
    assert main(["prog", str(bad)]) == 1
