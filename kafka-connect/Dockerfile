FROM confluentinc/cp-kafka-connect:7.5.0

# JMX exporter: конвертирует JMX-метрики Connect в формат Prometheus.
# Установка требует root — базовый образ по умолчанию работает от appuser.
USER root
RUN mkdir -p /opt/jmx_exporter && \
    curl -fsSL -o /opt/jmx_exporter/jmx_prometheus_javaagent.jar \
    https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.20.0/jmx_prometheus_javaagent-0.20.0.jar && \
    chmod 644 /opt/jmx_exporter/jmx_prometheus_javaagent.jar
USER appuser
