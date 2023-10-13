[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Tor Grafana Dashboards

Few dashboards for Tor relay, Tor Snowflake and the proposed DDoS solution.
Prometheus and Grafana run in the given example below at the same Tor relay where the DDoS solution is implemented.

## Prometheus

Prometheus is configured in this way:

```yaml
- job_name: "mr-fox"
  static_configs:
    - targets: ["localhost:9100"]

- job_name: "Tor-Bridge-Public"
  static_configs:
    - targets: ["borstel:9052", "casimir:9052", ....]

- job_name: "Tor-Snowflake"
  metrics_path: "/internal/metrics"
  static_configs:
    - targets: ["buddelflink:9999", "drehrumbum:9999", ....]

- job_name: "Tor"
  static_configs:
    - targets: ["localhost:19052"]
      labels:
        orport: "443"
    - targets: ["localhost:29052"]
      labels:
        orport: "9001"
```

The label `orport` is used as a filter for the DDoS dashboard.

## Scraping Tor Relay metrics

Configure the Tor metrics port, e.g.:

```config
MetricsPort 127.0.0.1:9052
MetricsPortPolicy accept 127.0.0.1
MetricsPortPolicy accept [::1]
```

## Scraping Snowflake metrics

Snowflake provides metrics under a non-default path and to localhost only.
To scrape metrics from a remote Prometheus while avoiding unauthorized requests from outside
use [this](https://github.com/toralf/tor-relays/blob/main/playbooks/roles/setup-snowflake/tasks/firewall.yaml#L10) Ansible role.
Whilst this solution lacks encryption (as a separate NGinx would provide) this solution is sane IMO if all systems run in the same providers network.
