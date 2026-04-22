import std/[strutils, strformat, tables]
import ./types, ./registry

proc escapeLabel(value: string): string =
  result = value
  result = result.replace("\\", "\\\\")
  result = result.replace("\"", "\\\"")
  result = result.replace("\n", "\\n")

proc formatLabels(labels: LabelKey, extra: openArray[(string, string)] = @[]): string =
  var parts: seq[string]
  for (k, v) in labels:
    parts.add(fmt"""{k}="{escapeLabel(v)}"""")
  for (k, v) in extra:
    parts.add(fmt"""{k}="{escapeLabel(v)}"""")
  if parts.len > 0:
    result = "{" & parts.join(",") & "}"

proc formatFloat(v: float64): string =
  if v == v.int.float and v < 1e15:
    result = $v.int
  else:
    result = $v

proc renderCounter*(c: Counter): string =
  result = fmt"# HELP {c.name} {c.help}" & "\n"
  result &= fmt"# TYPE {c.name} counter" & "\n"
  for labels, value in c.getValues():
    result &= c.name & formatLabels(labels) & " " & formatFloat(value) & "\n"

proc renderGauge*(g: Gauge): string =
  result = fmt"# HELP {g.name} {g.help}" & "\n"
  result &= fmt"# TYPE {g.name} gauge" & "\n"
  for labels, value in g.getValues():
    result &= g.name & formatLabels(labels) & " " & formatFloat(value) & "\n"

proc renderHistogram*(h: Histogram): string =
  result = fmt"# HELP {h.name} {h.help}" & "\n"
  result &= fmt"# TYPE {h.name} histogram" & "\n"
  for labels, data in h.getValues():
    let bucketCounts = data.getBucketCounts()
    var cumulative = 0.0
    for i, bound in h.buckets:
      cumulative += bucketCounts[i]
      let le = if bound == bound.int.float and bound < 1e15: $bound.int & ".0"
               else: $bound
      result &= h.name & "_bucket" & formatLabels(labels, {"le": le}) & " " & formatFloat(cumulative) & "\n"
    # +Inf bucket
    cumulative += bucketCounts[h.buckets.len]
    result &= h.name & "_bucket" & formatLabels(labels, {"le": "+Inf"}) & " " & formatFloat(cumulative) & "\n"
    result &= h.name & "_sum" & formatLabels(labels) & " " & $data.getSum() & "\n"
    result &= h.name & "_count" & formatLabels(labels) & " " & formatFloat(data.getCount()) & "\n"

proc renderMetrics*(): string =
  runCollectors()
  result = ""
  for metric in allMetrics():
    case metric.kind
    of mkCounter:
      result &= renderCounter(metric.counter)
    of mkGauge:
      result &= renderGauge(metric.gauge)
    of mkHistogram:
      result &= renderHistogram(metric.histogram)
