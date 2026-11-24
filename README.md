# YP_KAFKA_PRACTICE_5

# CDC-конвейер: Postgres → Kafka (Debezium) + мониторинг

Решение разворачивает end-to-end поток Change Data Capture (CDC): изменения в
базе Postgres через Debezium Connector попадают в кластер Kafka, а вся
инфраструктура покрыта мониторингом (Prometheus + Grafana) и управляется
через Kafka UI.

## Архитектура

''''                

                    +---------------------------------------------+
                    |                  kafka-net                   |
                    |                                              |
    Postgres ----> | kafka-connect (Debezium) --> kafka-1  --+     |
    (customers)    |   REST: 8083                 kafka-2  --+-->   Consumers
                    |   JMX: 9404                 kafka-3  --+    |
                    |        ^                                    |
                    |        |                   ^        v       |
                    |   prometheus <-- kafka-exporter (9308)      |
                    |        ^            postgres-exporter (9187)|
                    |        |                                    |
                    |     grafana (3000)     kafka-ui (8080)      |
                    |                        schema-registry(8081)|
                    +---------------------------------------------+


''''



**Поток данных:**
1. Приложение пишет в Postgres.
2. Debezium Connector читает WAL через логическую репликацию (`pgoutput`) и
   публикует события изменений (insert/update/delete) в топики Kafka.
3. Потребители читают события из Kafka напрямую или через Schema Registry (Avro).

**Поток метрик:**
- Kafka Connect экспортирует метрики через JMX Exporter на порт 9404.
- `kafka-exporter` забирает метрики брокеров и лаги консьюмер-групп по протоколу Kafka (9308).
- `postgres-exporter` снимает метрики СУБД (соединения, транзакции, кэш) по протоколу Postgres (9187).
- `prometheus` опрашивает все три источника и хранит временные ряды.
- `grafana` визуализирует данные из Prometheus.

## Состав компонентов

| Компонент | Образ | Порт (хост) | Назначение |
|---|---|---|---|
| zookeeper-1 | cp-zookeeper:7.5.0 | — | Координация брокеров Kafka (7.5.0 ещё требует ZK) |
| kafka-1..3 | cp-kafka:7.5.0 | 29092–29094 | Кластер из 3 брокеров. Внутренний слушатель `PLAINTEXT://kafka-N:9092` для контейнеров, внешний `PLAINTEXT_HOST://localhost:2909X` для хоста |
| schema-registry | cp-schema-registry:7.5.0 | 8081 | Хранение и валидация схем (Avro/Protobuf); нужен при переходе с JSON на Avro |
| postgres | debezium/postgres:16 | 15432 | Исходная БД с настроенной логической репликацией (`wal_level=logical`) |
| kafka-connect | собирается из `./kafka-connect` | 8083, 9404 | Движок коннекторов Debezium; 8083 — REST API, 9404 — метрики JMX Exporter |
| kafka-ui | provectuslabs/kafka-ui:v0.7.0 | 8080 | Веб-интерфейс: топики, консьюмер-группы, коннекторы |
| prometheus | prom/prometheus:v2.51.0 | 9090 | Сбор и хранение метрик; конфиг `./prometheus/prometheus.yml`, алерты `./prometheus/alerts.yml` |
| grafana | grafana/grafana:10.4.1 | 3000 | Дашборды; провижининг из `./grafana/provisioning` |
| kafka-exporter | danielqsj/kafka-exporter:v1.7.0 | 9308 | Метрики брокеров/топиков, лаги групп |
| postgres-exporter | prometheuscommunity/postgres-exporter:v0.15.0 | 9187 | Метрики Postgres |

**Взаимные зависимости:**
- брокеры ждут healthcheck Zookeeper (`condition: service_healthy`);
- Schema Registry и Kafka Connect ждут брокеров;
- kafka-connect дополнительно ждёт Schema Registry и Postgres (нужны для конвертеров и коннектора);
- grafana зависит от prometheus;
- экспортеры зависят от тех объектов, метрики которых снимают.

## Требования

- Docker Engine 24+ с плагином Compose v2
- 4–6 ГБ свободной оперативной памяти (суммарно стек поднимает 12 контейнеров)
- Свободные порты: 8080, 8081, 8083, 9308, 9404, 9187, 9090, 3000, 15432, 29092–29094

## Запуск и проверка работосопособности

```bash

make up            # поднять стек
make health        # убедиться, что всё готово
make ps            # статус
make logs          # смотреть логи
make down          # остановить (данные сохранятся)
make clean         # снести всё вместе с томами

# Создание таблиц в БД, нужно выполнить после первого старта
# появится список созданных таблиц
make init-db

# Создание и проверка коннектора
make connector-create
# В ответе должно быть "state": "RUNNING"
make connector-status

# Наполнение и работа с БД
make seed-db
# в одном терминале можно выполнять команды работы с БД, 
# а в другом запустить консьюмер который видит изменения через коннектор
make run-consumer

# примеры команд работы с БД
make delete-order ID=5
make delete-user ID=3
make update-user ID=3 NAME="Мария Сергеевна"
make update-user ID=3 EMAIL=maria@example.com
make update-user ID=3 NAME="Мария С." EMAIL=maria@example.com   # оба поля сразу
```
При этом консьюмер будет выводить 

```
------------------------------------------------------------
[users] CREATE
        ROW: id=9, name=Иван Иванович_9, email=user_9@example.com, created_at=1794747708483610
------------------------------------------------------------
[users] CREATE
        ROW: id=10, name=Иван Иванович_10, email=user_10@example.com, created_at=1794661308483610
------------------------------------------------------------
[orders] DELETE
        BEFORE: id=5, user_id=None, product_name=None, quantity=None, order_date=0
------------------------------------------------------------

```



## Мониторинг:

Kafka-UI http://localhost:8080/ui/
На странице должны быть вкладки со Schema Registry и Kafka Connect
Kafka Connect должен содержать коннектор postgres-source-yp5 в статусе RUNNING




Prometheus http://localhost:9090/

здесь http://localhost:9090/targets — все четыре джобы (kafka-connect, kafka-exporter, postgres-exporter, prometheus) в UP

Сырые метрики Connect: http://localhost:9404/metrics

Grafana: http://localhost:3000, логин/пароль admin/admin. Источник данных Prometheus: Configuration → Data Sources → Prometheus, URL http://prometheus:9090 → Save & test. Быстрая проверка запроса в Explore:
```
Можно добавить что-то из дашбордов прометеуса или выбрать существующие метрики
```
