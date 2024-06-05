[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Tor Grafana Dashboards

Few dashboards for Tor relays, Snowflake and the DDoS metrics.

![image](./tor-ddos-dashboard.jpg)

## Scraping Tor metrics

An Ansible example to scrape metrics is given [here](https://github.com/toralf/tor-relays/?tab=readme-ov-file#metrics).

A Prometheus config would look like this:

```yaml
- job_name: "Tor-Relay"
  metrics_path: "/metrics-relay"
  scheme: https
  tls_config:
    ca_file: "/etc/prometheus/CA.crt"
  static_configs:
    - targets: ["..."]
  relabel_configs:
    - source_labels: [__address__]
      target_label: instance
      regex: "([^:]+).*:(.).*"
      replacement: "nick${2}"
```
