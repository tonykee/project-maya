"""An Edit call is held whole; one cut off at EOS is text, never a truncated tool call (76K context, 2026-11-02).
    python -m unittest serve.test_buffer_edit"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from serve.frontend import DSML, OutputParser  # noqa: E402

TOOLS = [
    {"name": "Edit", "parameters": {"type": "object", "properties": {
        "path": {"type": "string"}, "old_string": {"type": "string"}, "new_string": {"type": "string"}}}},
    {"name": "Write", "parameters": {"type": "object", "properties": {
        "path": {"type": "string"}, "content": {"type": "string"}}}},
    {"name": "Bash", "parameters": {"type": "object", "properties": {"command": {"type": "string"}}}},
]
EDIT = ('<tool_call>Edit<arg_key>path</arg_key><arg_value>x.svg</arg_value>'
        '<arg_key>old_string</arg_key><arg_value>a</arg_value>'
        '<arg_key>new_string</arg_key><arg_value>b</arg_value></tool_call>')
INCOMPLETE = EDIT[:EDIT.index("<arg_key>new_string") + 30]
WRITE = ('<tool_call>Write<arg_key>path</arg_key><arg_value>x.svg</arg_value>'
         '<arg_key>content</arg_key><arg_value>hello</arg_value></tool_call>')
BASH = '<tool_call>Bash<arg_key>command</arg_key><arg_value>ls</arg_value></tool_call>'


def run(text: str, pieces: int | None = None, dsml: bool = False) -> list:
    p = OutputParser(thinking=False, tools=TOOLS, stream_tools=True, dsml=dsml)
    out = []
    step = pieces or len(text)
    for i in range(0, len(text), step):
        out += p.feed(text[i:i + step])
    return out + p.finish()


def calls(events) -> list:
    return [e.call for e in events if e.kind == "tool_call"]


def content(events) -> str:
    return "".join(e.text for e in events if e.kind == "content")


class EditIsHeldWhole(unittest.TestCase):
    def test_complete_edit_is_one_call_with_no_streamed_arguments(self):
        events = run(EDIT)
        self.assertEqual([(c.name, c.arguments) for c in calls(events)],
                         [("Edit", {"path": "x.svg", "old_string": "a", "new_string": "b"})])
        self.assertNotIn("tool_start", [e.kind for e in events])
        self.assertNotIn("tool_args", [e.kind for e in events])

    def test_complete_edit_character_by_character(self):
        events = run(EDIT, pieces=1)
        self.assertEqual([(c.name, c.arguments) for c in calls(events)],
                         [("Edit", {"path": "x.svg", "old_string": "a", "new_string": "b"})])
        self.assertNotIn("tool_args", [e.kind for e in events])

    def test_cut_off_edit_is_text_not_a_call(self):
        events = run(INCOMPLETE)
        self.assertEqual(calls(events), [])
        self.assertTrue(content(events).startswith("<tool_call>Edit"))
        self.assertIn("tool call cut off", content(events))

    def test_cut_off_edit_streamed_character_by_character_is_text(self):
        events = run(INCOMPLETE, pieces=1)
        self.assertEqual(calls(events), [])
        self.assertIn("tool call cut off", content(events))

    def test_a_write_still_streams(self):
        events = run(WRITE)
        self.assertIn("tool_start", [e.kind for e in events])
        self.assertIn("tool_args", [e.kind for e in events])
        self.assertEqual([(c.name, c.arguments) for c in calls(events)],
                         [("Write", {"path": "x.svg", "content": "hello"})])

    def test_bash_still_streams(self):
        events = run(BASH)
        self.assertIn("tool_start", [e.kind for e in events])
        self.assertEqual([(c.name, c.arguments) for c in calls(events)], [("Bash", {"command": "ls"})])

    def test_dsml_edit_is_held_whole(self):
        text = (f'<{DSML} calls>\n<{DSML} invoke name="Edit">\n'
                f'<{DSML} parameter name="path" string="true">x.svg</{DSML} parameter>\n'
                f'<{DSML} parameter name="old_string" string="true">a</{DSML} parameter>\n'
                f'<{DSML} parameter name="new_string" string="true">b</{DSML} parameter>\n'
                f'</{DSML} invoke>\n</{DSML} calls>')
        events = run(text, dsml=True)
        self.assertEqual([(c.name, c.arguments) for c in calls(events)],
                         [("Edit", {"path": "x.svg", "old_string": "a", "new_string": "b"})])
        self.assertNotIn("tool_start", [e.kind for e in events])

    def test_a_cut_off_dsml_edit_is_text(self):
        text = (f'<{DSML} calls>\n<{DSML} invoke name="Edit">\n'
                f'<{DSML} parameter name="path" string="true">x.svg</{DSML} parameter>\n'
                f'<{DSML} parameter name="old_string" string="true">a</{DSML} parameter>\n'
                f'<{DSML} parameter name="new_string" string="true">b</{DSML}')
        events = run(text, dsml=True)
        self.assertEqual(calls(events), [])


if __name__ == "__main__":
    unittest.main()
