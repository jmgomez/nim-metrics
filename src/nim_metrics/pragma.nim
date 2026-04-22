import std/[macros, monotimes, times]
import ./types, ./registry

var httpRequestsTotal {.global.}: Counter
var httpRequestDuration {.global.}: Histogram
var httpMetricsInitialized {.global.}: bool

proc ensureHttpMetrics() =
  if not httpMetricsInitialized:
    httpRequestsTotal = counter("http_requests_total", "Total HTTP requests")
    httpRequestDuration = histogram("http_request_duration_seconds", "HTTP request duration")
    httpMetricsInitialized = true

macro metrics*(route: static[string], prc: untyped): untyped =
  ## Pragma that wraps an async Prologue handler to auto-track HTTP metrics.
  ##
  ## Usage:
  ##   const RouteUsers = "/api/users"
  ##   proc getUsers(ctx: Context) {.async, metrics: RouteUsers.} =
  ##     resp ctx.json(users)
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
