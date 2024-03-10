[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

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

# Tor Grafana Dashboards

Few dashboards for Tor relay, Tor Snowflake and the proposed DDoS solution.
Prometheus and Grafana run in the given example below at the same machine.
The default scrape intervall of Prometheus is 15 sec here under a Gentoo Linux.
For Snowflake I set it to 1 min.
That's why 2 Grafana datasources are needed.
Each computes its specific `__rate_interval` accordingly to the choosen job.
