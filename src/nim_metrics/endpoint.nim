import prologue
import ./renderer

proc metricsHandler(ctx: Context) {.async.} =
  {.cast(gcsafe).}:
    let output = renderMetrics()
  ctx.response.setHeader("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
  resp output

proc useMetrics*(app: Prologue) =
  app.addRoute("/metrics", metricsHandler, HttpGet)
