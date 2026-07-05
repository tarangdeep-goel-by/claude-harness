# Daily job entry — reference

Add a job by appending one block to `System/daily-jobs.yaml`:

```yaml
  - name: <unique-slug>          # used as the freshness key in daily-jobs.jsonl
    cmd: "<command to run>"      # absolute paths; runs via bash -c
    freshness_hours: 24          # skip if a success is newer than this
    on_fail: warn                # warn | block  (block = /start-work flags it loudly)
    desc: "<one line: what it refreshes>"
```

Notes
- The runner (`System/scripts/run-daily-jobs.sh`) records each success in
  `~/vault/logs/daily-jobs.jsonl` with a timestamp; staleness is computed from there.
- Long jobs are fine — `/start-work` runs them once at day start. Keep heavy pulls here,
  not in per-session flows.
- Prefer pointing `cmd` at an existing entrypoint (e.g. `~/code/<repo>/run_daily.sh`)
  rather than inlining pipeline steps.
