#!/usr/bin/env bash
# ai-clear — deprecated no-op.
#
# This command used to unload Ollama chat models before large swarms on the old
# low-RAM setup. The current Mac is an AI workstation with enough RAM for local
# models and parallel agents, so automatic model unloading is now harmful.
set -u

cat <<'EOF'
ai-clear is deprecated and intentionally does not unload Ollama models.
Use explicit `ollama stop <model>` only when you personally want to unload a model.
Ready for agent swarm.
EOF
