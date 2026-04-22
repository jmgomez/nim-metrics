import std/locks
import ./types

type
  MetricRef* = object
    case kind*: MetricKind
    of mkCounter:
      counter*: Counter
    of mkGauge:
      gauge*: Gauge
    of mkHistogram:
      histogram*: Histogram

  Collector* = proc() {.gcsafe.}

  Registry* = ref object
    lock: Lock
    metrics: seq[MetricRef]
    collectors: seq[Collector]

var globalRegistry: Registry

proc getRegistry*(): Registry =
  if globalRegistry.isNil:
    globalRegistry = Registry()
    initLock(globalRegistry.lock)
  result = globalRegistry

proc register*(metric: MetricRef) =
  let reg = getRegistry()
  withLock reg.lock:
    reg.metrics.add(metric)

proc registerCollectorProc*(collector: Collector) =
  let reg = getRegistry()
  withLock reg.lock:
    reg.collectors.add(collector)

proc allMetrics*(): seq[MetricRef] =
  let reg = getRegistry()
  withLock reg.lock:
    result = reg.metrics

proc runCollectors*() =
  let reg = getRegistry()
  var collectors: seq[Collector]
  withLock reg.lock:
    collectors = reg.collectors
  for c in collectors:
    c()

# Convenience constructors that register automatically

proc counter*(name, help: string): Counter =
  result = newCounter(name, help)
  register(MetricRef(kind: mkCounter, counter: result))

proc gauge*(name, help: string): Gauge =
  result = newGauge(name, help)
  register(MetricRef(kind: mkGauge, gauge: result))

proc histogram*(name, help: string, buckets: seq[float64] = defaultBuckets): Histogram =
  result = newHistogram(name, help, buckets)
  register(MetricRef(kind: mkHistogram, histogram: result))

template registerCollector*(body: untyped) =
  registerCollectorProc(proc() {.gcsafe.} =
    {.cast(gcsafe).}:
      body
  )
