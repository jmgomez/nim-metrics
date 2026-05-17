import std/[macros, monotimes, times, locks]
import ./types, ./registry

# The HTTP metrics are shared across every kairos worker thread. The original
# `ensureHttpMetrics()` was an unguarded check-then-set:
#
#   if not httpMetricsInitialized:
#     httpRequestsTotal = counter(...)
#     httpMetricsInitialized = true
#
# Under NUM_THREADS≥2 with concurrent requests, two threads could pass the
# `if not initialized` check simultaneously. Both would allocate Counter
# objects, both would assign to the same {.global.} slot. A third thread
# mid-`inc()` could see a partially-constructed Counter whose `lock` field
# and `values` Table were not yet visible — and `mgetOrPut` would then crash
# inside `tableimpl.checkIfInitialized → initImpl` operating on garbage.
# This was the 2026-05-17 refc-NT=4 SIGSEGV. Fix: guard with a lock AND
# prefer startup-time init via `initHttpMetrics()`.

var httpRequestsTotal {.global.}: Counter
var httpRequestDuration {.global.}: Histogram
var httpMetricsInitialized {.global.}: bool
var httpMetricsInitLock {.global.}: Lock

# Bootstrap the init lock at module load — runs once on the main thread
# before any kairos worker exists, so there is no race on the lock itself.
initLock(httpMetricsInitLock)

proc initHttpMetrics*() =
  ## Initialize the HTTP request/duration metrics. Idempotent and lock-guarded
  ## so it is safe to call from anywhere — but the intended use is one
  ## explicit call from the main thread BEFORE the server accepts requests
  ## (so the runtime path on the pragma is a fast no-op).
  withLock httpMetricsInitLock:
    if not httpMetricsInitialized:
      httpRequestsTotal = counter("http_requests_total", "Total HTTP requests")
      httpRequestDuration = histogram("http_request_duration_seconds",
                                      "HTTP request duration")
      httpMetricsInitialized = true

proc ensureHttpMetrics*() {.gcsafe.} =
  ## Backwards-compatible fast path called from the pragma body. If
  ## `initHttpMetrics()` was already invoked at startup, this is a single
  ## bool read with no lock acquisition. Otherwise it falls back to the
  ## locked init path. Kept as a separate symbol so existing pragma-
  ## generated code continues to compile.
  if httpMetricsInitialized:
    return
  {.cast(gcsafe).}:
    initHttpMetrics()

macro metrics*(route: static[string], prc: untyped): untyped =
  ## Pragma that wraps an async Prologue handler to auto-track HTTP metrics.
  ##
  ## Usage:
  ##   const RouteUsers = "/api/users"
  ##   proc getUsers(ctx: Context) {.async, metrics: RouteUsers.} =
  ##     resp ctx.json(users)
  ##
  ## Note: callers SHOULD invoke `initHttpMetrics()` once at startup to
  ## eliminate the lazy-init path entirely. The fallback inside
  ## `ensureHttpMetrics()` is correct but adds a lock acquisition for the
  ## first request after process start.
  result = prc
  let body = prc.body

  let startTimeSym = genSym(nskLet, "metricsStartTime")
  let routeLit = newStrLitNode(route)

  let newBody = quote do:
    {.cast(gcsafe).}:
      ensureHttpMetrics()
    let `startTimeSym` = getMonoTime()
    try:
      `body`
    finally:
      let duration = (getMonoTime() - `startTimeSym`).inNanoseconds.float64 / 1_000_000_000.0
      let statusCode = $ctx.response.code.int
      let reqMethod = $ctx.request.reqMethod
      try:
        {.cast(gcsafe).}:
          httpRequestsTotal.inc(labels = {"method": reqMethod, "route": `routeLit`, "status_code": statusCode})
          httpRequestDuration.observe(duration, labels = {"method": reqMethod, "route": `routeLit`})
      except CatchableError:
        discard

  result.body = newBody
