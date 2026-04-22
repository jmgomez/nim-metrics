import std/[unittest, strutils, tables]
import nim_metrics/[types, registry, renderer]

suite "Counter":
  test "inc with default amount":
    let c = newCounter("test_counter_1", "A test counter")
    c.inc()
    c.inc()
    let vals = c.getValues()
    check vals[toLabelKey(@[])] == 2.0

  test "inc with custom amount":
    let c = newCounter("test_counter_2", "A test counter")
    c.inc(5.0)
    let vals = c.getValues()
    check vals[toLabelKey(@[])] == 5.0

  test "inc with labels":
    let c = newCounter("test_counter_3", "A test counter")
    c.inc(labels = {"method": "GET"})
    c.inc(labels = {"method": "GET"})
    c.inc(labels = {"method": "POST"})
    let vals = c.getValues()
    check vals[toLabelKey(@[("method", "GET")])] == 2.0
    check vals[toLabelKey(@[("method", "POST")])] == 1.0

  test "inc rejects negative amount":
    let c = newCounter("test_counter_4", "A test counter")
    expect AssertionDefect:
      c.inc(-1.0)

suite "Gauge":
  test "set value":
    let g = newGauge("test_gauge_1", "A test gauge")
    g.set(42.0)
    let vals = g.getValues()
    check vals[toLabelKey(@[])] == 42.0

  test "inc and dec":
    let g = newGauge("test_gauge_2", "A test gauge")
    g.set(10.0)
    g.inc()
    g.dec(3.0)
    let vals = g.getValues()
    check vals[toLabelKey(@[])] == 8.0

  test "set with labels":
    let g = newGauge("test_gauge_3", "A test gauge")
    g.set(1.0, labels = {"host": "a"})
    g.set(2.0, labels = {"host": "b"})
    let vals = g.getValues()
    check vals[toLabelKey(@[("host", "a")])] == 1.0
    check vals[toLabelKey(@[("host", "b")])] == 2.0

suite "Histogram":
  test "observe with default buckets":
    let h = newHistogram("test_hist_1", "A test histogram")
    h.observe(0.05)
    h.observe(0.5)
    h.observe(5.0)
    let vals = h.getValues()
    let data = vals[toLabelKey(@[])]
    check data.getCount() == 3.0
    check data.getSum() == 5.55

  test "observe with custom buckets":
    let h = newHistogram("test_hist_2", "A test histogram",
                         buckets = @[1.0, 5.0, 10.0])
    h.observe(0.5)
    h.observe(3.0)
    h.observe(7.0)
    h.observe(15.0)
    let vals = h.getValues()
    let data = vals[toLabelKey(@[])]
    let bc = data.getBucketCounts()
    # Per-bucket (non-cumulative) counts:
    # bucket 1.0: 0.5 → 1
    check bc[0] == 1.0
    # bucket 5.0: 3.0 → 1
    check bc[1] == 1.0
    # bucket 10.0: 7.0 → 1
    check bc[2] == 1.0
    # +Inf: 15.0 (doesn't fit in any bucket) → 1
    check bc[3] == 1.0
    check data.getCount() == 4.0

  test "observe with labels":
    let h = newHistogram("test_hist_3", "A test histogram",
                         buckets = @[1.0, 10.0])
    h.observe(0.5, labels = {"route": "/a"})
    h.observe(5.0, labels = {"route": "/b"})
    let vals = h.getValues()
    check vals.len == 2

suite "Renderer":
  test "renders counter in Prometheus format":
    let c = newCounter("render_counter", "Test counter for rendering")
    c.inc(labels = {"method": "GET"})
    c.inc(labels = {"method": "GET"})
    let output = renderCounter(c)
    check "# HELP render_counter Test counter for rendering" in output
    check "# TYPE render_counter counter" in output
    check """render_counter{method="GET"} 2""" in output

  test "renders gauge in Prometheus format":
    let g = newGauge("render_gauge", "Test gauge")
    g.set(42.5)
    let output = renderGauge(g)
    check "# TYPE render_gauge gauge" in output
    check "render_gauge 42.5" in output

  test "renders histogram in Prometheus format":
    let h = newHistogram("render_hist", "Test histogram",
                         buckets = @[1.0, 5.0])
    h.observe(0.5)
    h.observe(3.0)
    let output = renderHistogram(h)
    check "# TYPE render_hist histogram" in output
    check """render_hist_bucket{le="1.0"} 1""" in output
    check """render_hist_bucket{le="5.0"} 2""" in output  # cumulative: 1 + 1
    check """render_hist_bucket{le="+Inf"} 2""" in output  # cumulative: 2 + 0
    check "render_hist_sum" in output
    check "render_hist_count 2" in output

  test "escapes label values":
    let c = newCounter("escape_test", "Test escaping")
    c.inc(labels = {"msg": "hello \"world\"\nline2"})
    let output = renderCounter(c)
    check """msg="hello \"world\"\nline2"""" in output

suite "Registry":
  test "counter constructor registers automatically":
    let c = counter("reg_test_counter", "Auto-registered counter")
    let metrics = allMetrics()
    var found = false
    for m in metrics:
      if m.kind == mkCounter and m.counter.name == "reg_test_counter":
        found = true
        break
    check found

  test "collectors run on renderMetrics":
    let g = gauge("collector_test", "Collector test gauge")
    registerCollector:
      g.set(99.0)
    let output = renderMetrics()
    check "collector_test 99" in output
