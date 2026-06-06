#!/usr/bin/env bats
# 16_dashboard.bats — exercises ~/.eco/recipes/dashboard.sh

load '../../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "dashboard.sh: DESC and INPUTS headers present" {
  run grep -E '^# DESC:' "$HOME/.eco/recipes/dashboard.sh"
  assert_success
  run grep -E '^# INPUTS:' "$HOME/.eco/recipes/dashboard.sh"
  assert_success
}

@test "dashboard.sh: invokes open with ~/.eco/current/dashboard.html" {
  run bash "$HOME/.eco/recipes/dashboard.sh"
  assert_success
  assert_stub_called open
  assert_stub_args_contain open "$HOME/.eco/current/dashboard.html"
}

@test "dashboard.sh: exits 0" {
  run bash "$HOME/.eco/recipes/dashboard.sh"
  [ "$status" -eq 0 ]
}
