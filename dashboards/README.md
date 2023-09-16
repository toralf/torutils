[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Tor Grafana Dashboards

Few dashboards for Tor relay ([here](./tor-relay.json)), Tor Snowflake ([here](./tor-snowflake.json)) and the proposed DDoS solution ([here](./tor-ddos.json)).
The upload is made by the help of [node_exporter](https://github.com/prometheus/node_exporter).
Prometheus and Grafana run i n the given example at the same Tor relay where the DDoS solution is implemented.

## Prometheus

Prometheus is configured in this way:

```yaml
- job_name: "mr-fox"
  static_configs:
    - targets: ["localhost:9100"]

- job_name: "Tor-Bridge-Public"
  static_configs:
    - targets:
        [
          "borstel:9052",
          "casimir:9052",
          ....
        ]

- job_name: "Tor-Snowflake"
  metrics_path: "/internal/metrics"
  static_configs:
    - targets:
        [
          "buddelflink:9999",
          "drehrumbum:9999",
          ....
        ]

- job_name: "Tor"
  static_configs:
    - targets: ["localhost:19052"]
      labels:
        orport: "443"
    - targets: ["localhost:29052"]
      labels:
        orport: "9001"
    - targets: ["localhost:39052"]
      labels:
        orport: "8443"
    - targets: ["localhost:49052"]
      labels:
        orport: "9443"
    - targets: ["localhost:59052"]
      labels:
        orport: "5443"
```

The label `orport` is used as a filter for the DDoS dashboard.

## scraping Snowflake metrics

Snowflake provides metrics under a non-default path and to localhost only.
To scrape metrics from a remote Prometheus I added 2 iptables rules and set 1 sysctl value as seen in
([this](https://github.com/toralf/tor-relays/blob/main/playbooks/roles/setup-snowflake/tasks/firewall.yaml#L10))
to deploy Tor bridges and Snowflake.

Whilst this solution lacks encryption (as a separate NGinx would provide) this solution is sane IMO if all systems run in the same provider network.
