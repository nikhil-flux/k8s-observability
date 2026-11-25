# Kubernetes Observability Platform

Metrics, dashboards and alerting for a Kubernetes cluster using **Prometheus**, **Grafana** and **Alertmanager**, deployed with the `kube-prometheus-stack` Helm chart on a local **kind** cluster. Alerts are tested with `promtool` in CI.

## Architecture

```
app pods (/metrics) ─┐
node-exporter ───────┼──▶ Prometheus ──▶ Alertmanager ──▶ Slack
kube-state-metrics ──┘        │
                              └──▶ Grafana (dashboards)
```

| Component | Purpose |
|---|---|
| Prometheus Operator | Turns `ServiceMonitor` / `PrometheusRule` CRDs into Prometheus config |
| Prometheus | Scrapes, stores and evaluates rules |
| Alertmanager | Groups, deduplicates and routes alerts to Slack |
| Grafana | Dashboards, loaded from ConfigMaps by a sidecar |
| node-exporter / kube-state-metrics | Node and Kubernetes object metrics |
| demo-app + load-generator | Sample workload with RED metrics |

## Repo layout

```
kind-config.yaml            1 control-plane + 2 workers
helm/values.yaml            kube-prometheus-stack config (incl. Alertmanager routing)
demo-app/                   sample app, ServiceMonitor, load generator
alerts/prometheus-rule.yaml alert rules (PrometheusRule CRD)
alertmanager/               Slack secret template
dashboards/                 Grafana dashboard as a ConfigMap
tests/                      promtool unit tests
.github/workflows/          CI: promtool + yamllint + helm template
Makefile                    one-command workflows
```

## Prerequisites

`docker`, `kind`, `kubectl`, `helm`. For linting: `promtool` and `yq` (v4, mikefarah).

## Quick start

```bash
make up                                   # cluster + stack + demo app + rules + dashboard
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/... make slack-secret

make port-forward-grafana                 # http://localhost:3000  (admin / admin)
make port-forward-prometheus              # http://localhost:9090
make port-forward-alertmanager            # http://localhost:9093
```

Open Grafana, then **Dashboards → Demo app - RED metrics**.

## Trigger an alert

```bash
make break    # scales demo-app to 0 → DemoAppDown fires after ~1 min
make fix      # restore
```

Watch it move through Pending → Firing in Prometheus (**Alerts**), then see the Slack message. For the error-rate alert, raise the error share: `kubectl -n demo set env deploy/load-generator ERROR_EVERY=3`.

## Alerts

| Alert | Condition | Severity |
|---|---|---|
| DemoAppDown | no healthy demo-app targets for 1m | critical |
| DemoAppHighErrorRate | >5% 4xx/5xx for 5m | warning |
| DemoAppHighLatencyP95 | p95 > 500ms for 10m | warning |
| PodCrashLooping | >3 restarts in 15m | critical |
| PodNotReady | Pending/Unknown/Failed for 10m | warning |
| NodeHighCPU | >85% for 10m | warning |
| NodeHighMemory | >90% for 10m | warning |

Critical alerts inhibit warnings with the same name and namespace.

## Testing rules

```bash
make lint   # promtool check rules
make test   # promtool unit tests
```

The same checks run in GitHub Actions on every push.

## Design notes

- **kind control-plane scraping disabled.** etcd, scheduler, controller-manager and kube-proxy bind to localhost on kind, so scraping them only creates false "target down" alerts. Re-enable them on real clusters.
- **Selector settings.** `*SelectorNilUsesHelmValues: false` lets Prometheus pick up monitors and rules from any namespace, not just those labelled with the Helm release.
- **Secrets.** The Slack webhook lives in a Kubernetes Secret mounted into Alertmanager (`api_url_file`), never in Git.
- **Dashboards as code.** Grafana's sidecar loads any ConfigMap labelled `grafana_dashboard: "1"`.
- The example app returns 404 on `/err`, so the error-rate alert counts 4xx as errors for demo purposes. Use 5xx only for real services.

## Cleanup

```bash
make down
```

## Next steps

- Persistent storage for Prometheus and Grafana
- Ingress for Grafana
- Loki for logs
- Remote-write or Thanos for long-term storage
- Argo CD to manage the stack via GitOps
