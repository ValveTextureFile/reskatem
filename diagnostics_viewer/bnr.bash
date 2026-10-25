#!/bin/sh
cmake -S . -B build && cmake --build build && ./build/diagnostics_viewer