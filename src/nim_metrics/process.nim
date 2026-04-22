import std/[monotimes, times, strutils]
import ./types, ./registry

when defined(linux):
  proc getResidentMemoryBytes(): float64 =
    try:
      let status = readFile("/proc/self/status")
      for line in status.splitLines():
        if line.startsWith("VmRSS:"):
          let parts = line.splitWhitespace()
          if parts.len >= 2:
            result = parseFloat(parts[1]) * 1024.0 # kB to bytes
            return
    except:
      discard

elif defined(macosx):
  {.emit: """
  #include <mach/mach.h>
  #include <mach/task_info.h>

  static double nim_get_resident_memory() {
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                 (task_info_t)&info, &count);
    if (kr == KERN_SUCCESS) {
      return (double)info.resident_size;
    }
    return 0.0;
  }
  """.}

  proc getResidentMemoryBytes(): float64 {.importc: "nim_get_resident_memory", nodecl.}

else:
  proc getResidentMemoryBytes(): float64 = 0.0

let processStartTime = getMonoTime()

proc initProcessMetrics*() =
  let uptime = gauge("process_uptime_seconds", "Process uptime in seconds")
  let memory = gauge("process_resident_memory_bytes", "Resident memory size in bytes")

  registerCollector:
    let elapsed = (getMonoTime() - processStartTime).inNanoseconds.float64 / 1_000_000_000.0
    uptime.set(elapsed)
    memory.set(getResidentMemoryBytes())

# Auto-initialize on import
initProcessMetrics()
