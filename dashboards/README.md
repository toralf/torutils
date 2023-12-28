[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Tor Grafana Dashboards

Few dashboards for Tor relay, Tor Snowflake and the proposed DDoS solution.
Prometheus and Grafana run in the given example below at the same machine where few Tor relays are running and protected by the proposed DDoS solution ([README](../README.md)).
The default scrape intervall of Prometheus is 15 sec here under a Gentoo Linux, so for the Snowflake job it is set explicitely to 1 min.
That's why in Grafana 2 datasources are needed to let it compute its `__rate_interval` correctly accordingly to the choosen job.

**Hint**: Do only scrape in the same network (ideally at the same machine). Otherwise the Prometheus network traffic could unveil a Tor system.

## Prometheus

Prometheus is configured in this way:

```yaml
- job_name: "Node-Exporter"
  static_configs:
    - targets: ["localhost:9100"]

- job_name: "Tor-Bridge-Public"
  static_configs:
    - targets: ["borstel:9052", "casimir:9052", ...]
  relabel_configs:
    - source_labels: [__address__]
      regex: "(.*):(.*)"
      replacement: "${1}"
      target_label: instance

- job_name: "Tor-Snowflake-1m"
  scrape_interval: 1m
  metrics_path: "/internal/metrics"
  static_configs:
    - targets: ["buddelflink:9999", "drehrumbum:9999", ...]
  relabel_configs:
    - source_labels: [__address__]
      regex: "(.*):(.*)"
      replacement: "${1}"
      target_label: instance

- job_name: "Tor"
  static_configs:
    - targets: ["localhost:9052", ...]
      labels:
        instance: "my-nickname"
        nickname: "my-nickname"
```

## Scraping Tor Relay metrics

Configure the Tor metrics port, e.g.:

```config
MetricsPort 127.0.0.1:9052
MetricsPortPolicy accept 127.0.0.1
```

## Scraping Snowflake metrics

Snowflake provides metrics under a non-default path and to `localhost` only.
To scrape metrics from a remote Prometheus I do use
[this](https://github.com/toralf/tor-relays/blob/main/playbooks/roles/setup-snowflake/tasks/firewall.yaml#L10) Ansible task
to configure the Snowflake clients in the right way.
This solution lacks encryption.
Nevertheless, this solution looks sane for me because all systems run within the network of the same provider.
