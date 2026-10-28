"""Read-only CPU sampling for a named app PID during manual UI regression."""
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path

pid, seconds, destination = int(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])

def cpu_time(value):
    days = 0
    if '-' in value:
        raw_days, value = value.split('-', 1)
        days = int(raw_days)
    parts = list(map(float, value.split(':')))
    result = days * 86400
    for part, factor in zip(reversed(parts), [1, 60, 3600]):
        result += part * factor
    return result

started = time.monotonic()
previous = None
samples = []
run = longest = 0
with destination.open('w') as output:
    while time.monotonic() - started <= seconds:
        result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'time=', '-o', 'state='], capture_output=True, text=True)
        values = result.stdout.split()
        if len(values) < 2:
            raise SystemExit('App exited during observation')
        now = time.monotonic()
        cumulative = cpu_time(values[0])
        use = 0 if previous is None else max(0, (cumulative - previous[1]) / (now - previous[0]) * 100)
        sample = {'elapsed_s': round(now - started, 2), 'cpu_percent_interval': round(use, 2), 'cpu_time_s': cumulative, 'state': values[1]}
        output.write(json.dumps(sample) + '\n'); output.flush()
        if previous is not None:
            samples.append(use)
            run = run + 1 if use > 80 else 0
            longest = max(longest, run)
        previous = now, cumulative
        time.sleep(1)
summary = {'duration_s': round(time.monotonic() - started, 1), 'samples': len(samples), 'median_cpu_percent': round(statistics.median(samples), 2), 'max_cpu_percent': round(max(samples), 2), 'longest_over_80_percent_s': longest}
print(json.dumps(summary))
destination.with_suffix('.summary.json').write_text(json.dumps(summary, indent=2))
if longest >= 5:
    raise SystemExit('Sustained high CPU detected; regression failed')
