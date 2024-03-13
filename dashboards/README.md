[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Tor Grafana Dashboards

Few dashboards for Tor relays, Tor Snowflake and the proposed DDoS solution.

![image](./tor-ddos-dashboard.jpg)

## Scraping Tor metrics

To scrape metrics I do use [this](https://github.com/toralf/tor-relays/) Ansible task.
That task deploys Tor relays and Snowflake clients in an easy and reliable manner.
In addition if deploys and configures to each system to securely transmit data.

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
