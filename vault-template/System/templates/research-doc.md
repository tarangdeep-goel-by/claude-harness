---
title: "{{Analysis title}}"
categories:
  - "[[Research]]"
subjects:
  - "[[Growth & Metrics]]"
status: draft
created: {{date}}
updated: {{date}}
sources: [{{your data sources — e.g. mixpanel | posthog | metabase | bigquery | csv}}]
script: "{{~/code/<repo>/scripts/<name>.py}}"
---

# {{Analysis title}}

## Question
{{the precise question this analysis answers}}

## Method
- Lib + clients: {{data clients / methods / funnels used}}
- Window: {{date range}} · Cohort/segment: {{ids}}
- Script: `{{path}}` (run: `{{command}}`)

## Findings
{{numbers first — tables/bullets. Lead with the answer.}}

## Caveats / data-quality flags
- {{sampling, freshness, known gaps, dual-source drift, etc.}}

## Links
- Methodology: [[methodology]]
- Related: {{prior research, decisions}}
