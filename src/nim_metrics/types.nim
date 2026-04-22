import std/[tables, locks, hashes]

type
  MetricKind* = enum
    mkCounter
    mkGauge
    mkHistogram

  Labels* = openArray[(string, string)]
  LabelKey* = seq[(string, string)]

  Counter* = ref object
    name*: string
    help*: string
    lock: Lock
    values: Table[LabelKey, float64]

  Gauge* = ref object
    name*: string
    help*: string
    lock: Lock
    values: Table[LabelKey, float64]

  HistogramData = object
    bucketCounts: seq[float64]
    sum: float64
    count: float64

  Histogram* = ref object
    name*: string
    help*: string
    buckets*: seq[float64]
    lock: Lock
    values: Table[LabelKey, HistogramData]

const defaultBuckets* = @[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]

proc toLabelKey*(labels: Labels): LabelKey =
  result = @[]
  for (k, v) in labels:
    result.add((k, v))

proc hash*(key: LabelKey): Hash =
  var h: Hash = 0
  for (k, v) in key:
    h = h !& hash(k)
    h = h !& hash(v)
  result = !$h

# Counter operations

proc newCounter*(name, help: string): Counter =
  result = Counter(name: name, help: help)
  initLock(result.lock)

proc inc*(c: Counter, amount: float64 = 1.0, labels: Labels = @[]) {.gcsafe.} =
  assert amount >= 0, "Counter can only increase"
  let key = toLabelKey(labels)
  {.cast(gcsafe).}:
    withLock c.lock:
      c.values.mgetOrPut(key, 0.0) += amount

proc getValues*(c: Counter): Table[LabelKey, float64] {.gcsafe.} =
  {.cast(gcsafe).}:
    withLock c.lock:
      result = c.values

# Gauge operations

proc newGauge*(name, help: string): Gauge =
  result = Gauge(name: name, help: help)
  initLock(result.lock)

proc set*(g: Gauge, value: float64, labels: Labels = @[]) {.gcsafe.} =
  let key = toLabelKey(labels)
  {.cast(gcsafe).}:
    withLock g.lock:
      g.values[key] = value

proc inc*(g: Gauge, amount: float64 = 1.0, labels: Labels = @[]) {.gcsafe.} =
  let key = toLabelKey(labels)
  {.cast(gcsafe).}:
    withLock g.lock:
      g.values.mgetOrPut(key, 0.0) += amount

proc dec*(g: Gauge, amount: float64 = 1.0, labels: Labels = @[]) {.gcsafe.} =
  let key = toLabelKey(labels)
  {.cast(gcsafe).}:
    withLock g.lock:
      g.values.mgetOrPut(key, 0.0) -= amount

proc getValues*(g: Gauge): Table[LabelKey, float64] {.gcsafe.} =
  {.cast(gcsafe).}:
    withLock g.lock:
      result = g.values

# Histogram operations

proc newHistogram*(name, help: string, buckets: seq[float64] = defaultBuckets): Histogram =
  result = Histogram(name: name, help: help, buckets: buckets)
  initLock(result.lock)

proc observe*(h: Histogram, value: float64, labels: Labels = @[]) {.gcsafe.} =
  let key = toLabelKey(labels)
  {.cast(gcsafe).}:
    withLock h.lock:
      if key notin h.values:
        h.values[key] = HistogramData(
          bucketCounts: newSeq[float64](h.buckets.len + 1), # +1 for +Inf
          sum: 0.0,
          count: 0.0
        )
      var data = addr h.values[key]
      data.sum += value
      data.count += 1.0
      # Find the first bucket where value fits, or +Inf
      var placed = false
      for i, bound in h.buckets:
        if value <= bound:
          data.bucketCounts[i] += 1.0
          placed = true
          break
      if not placed:
        # Falls into +Inf bucket only
        data.bucketCounts[h.buckets.len] += 1.0

proc getValues*(h: Histogram): Table[LabelKey, HistogramData] {.gcsafe.} =
  {.cast(gcsafe).}:
    withLock h.lock:
      result = h.values

proc getBucketCounts*(data: HistogramData): seq[float64] =
  data.bucketCounts

proc getSum*(data: HistogramData): float64 =
  data.sum

proc getCount*(data: HistogramData): float64 =
  data.count
