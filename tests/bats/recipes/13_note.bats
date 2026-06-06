#!/usr/bin/env bats
# 13_note.bats — exercises ~/.eco/recipes/note.sh

load '../../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "note.sh: DESC and INPUTS headers present" {
  run grep -E '^# DESC:' "$HOME/.eco/recipes/note.sh"
  assert_success
  run grep -E '^# INPUTS:' "$HOME/.eco/recipes/note.sh"
  assert_success
}

@test "note.sh: CLI-arg mode at HOME writes file under spaces/unified" {
  # Running from $HOME (no project root) lands in the catch-all "unified" space.
  run bash -c 'cd "$HOME" && bash "$HOME/.eco/recipes/note.sh" "hello world"'
  assert_success
  assert_output_contains "Space: unified"
  assert_output_contains "Note saved"
  # Find the resulting file
  local unified_dir="$HOME/.ai-memory/spaces/unified"
  [ -d "$unified_dir" ]
  local note_file
  note_file="$(ls "$unified_dir"/note-*.md 2>/dev/null | head -1)"
  [ -n "$note_file" ]
  run cat "$note_file"
  assert_output_contains "hello world"
}

@test "note.sh: CWD inside a project dir routes to project-<basename> space" {
  # The space name is derived generically from the project directory basename,
  # not from any hardcoded list of project names.
  mkdir -p "$HOME/projects/demo-project"
  run bash -c 'cd "$HOME/projects/demo-project" && bash "$HOME/.eco/recipes/note.sh" "demo test note"'
  assert_success
  assert_output_contains "Space: project-demo-project"
  local space_dir="$HOME/.ai-memory/spaces/project-demo-project"
  [ -d "$space_dir" ]
  local note_file
  note_file="$(ls "$space_dir"/note-*.md 2>/dev/null | head -1)"
  [ -n "$note_file" ]
  run cat "$note_file"
  assert_output_contains "demo test note"
}

@test "note.sh: project basename is slugified into the space name" {
  # A directory name with uppercase/spaces/punctuation is normalized to a slug.
  mkdir -p "$HOME/projects/My Demo Repo"
  run bash -c 'cd "$HOME/projects/My Demo Repo" && bash "$HOME/.eco/recipes/note.sh" "slug note"'
  assert_success
  assert_output_contains "Space: project-my-demo-repo"
  local space_dir="$HOME/.ai-memory/spaces/project-my-demo-repo"
  [ -d "$space_dir" ]
  local note_file
  note_file="$(ls "$space_dir"/note-*.md 2>/dev/null | head -1)"
  [ -n "$note_file" ]
  run cat "$note_file"
  assert_output_contains "slug note"
}

@test "note.sh: after successful note, memory_router rebuild is attempted" {
  run bash "$HOME/.eco/recipes/note.sh" "trigger rebuild"
  assert_success
  [ -s "$HOME/.stub-python3.log" ]
  run cat "$HOME/.stub-python3.log"
  assert_output_contains "memory_router.py"
  assert_output_contains "--build-space"
}

@test "note.sh: empty editor buffer aborts with exit 1 and 'Empty note'" {
  # Wave 3 fix: tmpfile is created empty (no template pre-populated), so
  # an editor that writes nothing leaves CONTENT whitespace-only and the
  # guard fires. Using EDITOR=true — it exits 0 immediately without
  # touching the tmpfile.
  run env EDITOR=true bash "$HOME/.eco/recipes/note.sh"
  assert_failure 1
  assert_output_contains "Empty note"
}
