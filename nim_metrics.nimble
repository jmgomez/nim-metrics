# Package
version       = "0.1.0"
author        = "jmgomez"
description   = "Prometheus-compatible instrumentation library for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.0"
requires "prologue#head[kairos]"

task test, "Run tests":
  exec "nim c -r --threads:on --path:src tests/tall.nim"
