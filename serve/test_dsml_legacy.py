"""A DeepSeek-V4.1 call whose DSML special tokens were lost at a long context (`<parameter name=...>` with
`</arg_value>` / `</tool_call>` closers) read back as a call; text that only looks like one stays text.
    python -m unittest serve.test_dsml_legacy"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from serve.frontend import DSML, OutputParser  # noqa: E402

TOOLS = [
    {"name": "Bash", "parameters": {"type": "object", "properties": {
        "command": {"type": "string"}, "timeout": {"type": "integer"}}}},
    {"name": "Read", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}}},
]


def run(text: str, pieces: int | None = None, tools=TOOLS) -> list:
    p = OutputParser(thinking=False, tools=tools, stream_tools=True, dsml=True)
    out = []
    step = pieces or len(text)
    for i in range(0, len(text), step):
        out += p.feed(text[i:i + step])
    return out + p.finish()


def calls(events) -> list:
    return [e.call for e in events if e.kind == "tool_call"]


def content(events) -> str:
    return "".join(e.text for e in events if e.kind == "content")


BARE = '<parameter name="command" string="true">cd /tmp && ls -la</arg_value>\n</tool_call>'


class LegacyCalls(unittest.TestCase):
    def test_whole(self):
        c = calls(run(BARE))
        self.assertEqual([(x.name, x.arguments) for x in c], [("Bash", {"command": "cd /tmp && ls -la"})])

    def test_streamed_character_by_character(self):
        c = calls(run(BARE, pieces=1))
        self.assertEqual([(x.name, x.arguments) for x in c], [("Bash", {"command": "cd /tmp && ls -la"})])

    def test_string_attribute_missing(self):
        text = '<parameter name="command">cd /tmp && ls -la</parameter>\n</tool_call>'
        c = calls(run(text))
        self.assertEqual([(x.name, x.arguments) for x in c], [("Bash", {"command": "cd /tmp && ls -la"})])

    def test_several_parameters_with_types(self):
        text = ('<parameter name="command" string="true">ls</parameter>\n'
                '<parameter name="timeout" string="false">30</arg_value>\n</tool_call>')
        c = calls(run(text))
        self.assertEqual([(x.name, x.arguments) for x in c], [("Bash", {"command": "ls", "timeout": 30})])

    def test_content_before_the_call_is_kept(self):
        events = run("Let me look.\n\n" + BARE)
        self.assertEqual(content(events), "Let me look.")
        self.assertEqual([x.name for x in calls(events)], ["Bash"])

    def test_surviving_wrapper_name(self):
        text = '<invoke name="Bash">\n' + BARE
        c = calls(run(text))
        self.assertEqual([(x.name, x.arguments) for x in c], [("Bash", {"command": "cd /tmp && ls -la"})])

    def test_a_surviving_tool_call_opener(self):
        text = "<tool_call>\n" + BARE
        for pieces in (None, 1, 7):
            c = calls(run(text, pieces=pieces))
            self.assertEqual([(x.name, x.arguments) for x in c],
                             [("Bash", {"command": "cd /tmp && ls -la"})], pieces)

    def test_a_proper_qwen_call_in_dsml_mode_is_unchanged(self):
        text = ("<tool_call>\n<function=Bash>\n<parameter=command>\nls\n</parameter>\n</function>\n"
                "</tool_call>")
        c = calls(run(text))
        self.assertEqual([(x.name, x.arguments) for x in c], [("Bash", {"command": "ls"})])

    def test_a_bare_block_in_the_thinking_stays_reasoning(self):
        p = OutputParser(thinking=True, tools=TOOLS, stream_tools=True, dsml=True, token_only_end=True)
        out = p.feed("I could write " + BARE)
        out += p.close_reasoning()
        out += p.feed(BARE)
        out += p.finish()
        self.assertIn(BARE, "".join(e.text for e in out if e.kind == "reasoning"))
        self.assertEqual([(x.name, x.arguments) for x in calls(out)],
                         [("Bash", {"command": "cd /tmp && ls -la"})])

    def test_a_parameter_no_tool_declares_stays_text(self):
        text = '<parameter name="nope" string="true">x</arg_value>\n</tool_call>'
        events = run(text)
        self.assertEqual(calls(events), [])
        self.assertEqual(content(events), text)

    def test_text_after_the_closing_tag_stays_text(self):
        text = BARE + "\nand then some prose"
        events = run(text)
        self.assertEqual(calls(events), [])
        self.assertEqual(content(events), text)

    def test_a_parameter_tag_in_prose_is_not_a_call(self):
        text = 'The template is `<parameter name="command" string="true">`, as shown.'
        events = run(text)
        self.assertEqual(calls(events), [])
        self.assertEqual(content(events), text)

    def test_one_tool_without_a_name(self):
        text = BARE
        c = calls(run(text, tools=TOOLS[:1]))
        self.assertEqual([x.name for x in c], ["Bash"])

    def test_proper_dsml_is_unchanged(self):
        text = (f'<{DSML} calls>\n<{DSML} invoke name="Bash">\n'
                f'<{DSML} parameter name="command" string="true">cd /tmp</{DSML} parameter>\n'
                f'</{DSML} invoke>\n</{DSML} calls>')
        c = calls(run(text))
        self.assertEqual([(x.name, x.arguments) for x in c], [("Bash", {"command": "cd /tmp"})])

    def test_a_string_value_with_quotes_survives(self):
        text = '<parameter name="command" string="true">echo "hi" &amp;&amp; ls</arg_value>\n</tool_call>'
        c = calls(run(text))
        self.assertEqual([x.arguments for x in c], [{"command": 'echo "hi" &amp;&amp; ls'}])


if __name__ == "__main__":
    unittest.main()
