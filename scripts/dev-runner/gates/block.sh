#!/usr/bin/env bash
# Prints the fenced ```gate block of a plan file (empty when absent). Single owner of the extraction.
set -euo pipefail
awk '/^```gate[[:space:]]*$/{f=1; next} f && /^```/{exit} f' "$1"
