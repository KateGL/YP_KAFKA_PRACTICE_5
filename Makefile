# ================== Переменные ==================
COMPOSE = docker compose
# Сервисы инфраструктуры без kafka-connect (его надо собирать отдельно)
INFRA   = zookeeper-1 kafka-1 kafka-2 kafka-3 schema-registry postgres

.PHONY: help up down restart build rebuild logs ps status health clean topics connect-check ui-shell init-db seed-db connector-create connector-status connector-delete delete-order delete-user update-user run-consumer clean-consumer-venv

# ================== Справка ==================
help: ## Показать список команд
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# ================== Запуск и остановка ==================
up: ## Запустить весь стек (сборка kafka-connect, ожидание готовности Zookeeper)
	$(COMPOSE) up -d --build
	@echo "Стек запускается. Проверить готовность: make health"

down: ## Остановить стек (данные в томах сохраняются)
	$(COMPOSE) down

restart: ## Перезапустить стек
	$(COMPOSE) down
	$(COMPOSE) up -d --build

clean: ## Полный сброс: остановить и удалить данные (тома!)
	$(COMPOSE) down -v
	@echo "Внимание: все топики, схемы и данные Postgres удалены."

rebuild: ## Пересобрать образ kafka-connect и перезапустить его
	$(COMPOSE) up -d --build --force-recreate kafka-connect

# ================== Наблюдение ==================
logs: ## Логи всех сервисов (поток)
	$(COMPOSE) logs -f --tail=100

logs-kafka: ## Логи брокеров Kafka
	$(COMPOSE) logs -f --tail=100 kafka-1 kafka-2 kafka-3

logs-connect: ## Логи Kafka Connect
	$(COMPOSE) logs -f --tail=100 kafka-connect

ps: ## Статус контейнеров
	$(COMPOSE) ps

status: ## Статус + краткая сводка
	$(COMPOSE) ps
	@echo ""
	@echo "Порты на хосте:"
	@echo "  Kafka (host listeners): 29092 / 29093 / 29094"
	@echo "  Schema Registry:        127.0.0.1:8081"
	@echo "  Kafka Connect REST:     8083"
	@echo "  Kafka UI:               8080"
	@echo "  Postgres:               15432"

# ================== Проверки готовности ==================
health: ## Проверить готовность ключевых сервисов
	@echo "--- Zookeeper ---"
	@docker exec zookeeper-1 bash -c 'echo srvr | nc -w 2 localhost 2181 | grep "Zookeeper version"' || echo "ZK не готов"
	@echo "--- Kafka (bootstrap kafka-1) ---"
	@docker exec kafka-1 kafka-topics --bootstrap-server localhost:9092 --list >/dev/null 2>&1 && echo "OK" || echo "Брокер не готов"
	@echo "--- Schema Registry ---"
	@curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8081/subjects || echo "SR не готов"
	@echo "--- Kafka Connect ---"
	@curl -s http://localhost:8083/connectors || echo "Connect не готов"

connect-check: ## Список коннекторов и статусы плагинов
	@echo "--- Плагины Connect ---"
	@curl -s http://localhost:8083/connector-plugins
	@echo ""
	@echo "--- Коннекторы ---"
	@curl -s http://localhost:8083/connectors

# ================== Работа с Kafka ==================
topics: ## Список топиков
	@docker exec kafka-1 kafka-topics --bootstrap-server localhost:9092 --list

create-topic: ## Создать топик: make create-topic TOPIC=my-topic PARTITIONS=3
	@docker exec kafka-1 kafka-topics \
		--bootstrap-server localhost:9092 \
		--create --if-not-exists \
		--topic $(TOPIC) \
		--partitions $(PARTITIONS) \
		--replication-factor 1
	@echo "Топик $(TOPIC) создан/уже существует."

# ================== Оболочки ==================
kafka-shell: ## Войти в контейнер kafka-1
	docker exec -it kafka-1 bash

pg-shell: ## Войти в psql (postgres)
	docker exec -it postgres psql -U postgres-user -d customers

ui-shell: ## Войти в контейнер kafka-connect (для отладки коннекторов)
	docker exec -it kafka-connect bash

# ================== База данных ==================
init-db: ## Создать БД db_yp5 и таблицы users/orders
	@echo "Создание БД и таблиц..."
	@docker exec -i postgres psql -U postgres-user -d customers \
		-v ON_ERROR_STOP=0 \
		< ./db/init.sql
	@echo "Готово. Проверка таблиц:"
	@docker exec -i postgres psql -U postgres-user -d db_yp5 -c "\dt"

seed-db: ## Наполнить базу тестовыми данными: make seed-db [USERS=10] [ORDERS=3]
	./db/seed_db.sh db_yp5 ${USERS} ${ORDERS}

delete-order: ## Удалить заказ по ID: make delete-order ID=5
	./db/user_ops.sh delete-order $(ID)

delete-user: ## Удалить пользователя по ID: make delete-user ID=3
	./db/user_ops.sh delete-user $(ID)

update-user: ## Изменить пользователя: make update-user ID=3 NAME="Мария Сергеевна" [EMAIL=...]
	@if [ -z "$(ID)" ]; then echo "Использование: make update-user ID=<номер> [NAME=...] [EMAIL=...]"; exit 1; fi
	NAME='$(NAME)' EMAIL='$(EMAIL)' ./db/user_ops.sh update-user $(ID)


# ====== Connectors =====
connector-create: ## Создать Debezium-коннектор из kafka-connect/connectors/postgres-source.json
	curl -s -X POST http://localhost:8083/connectors \
		-H "Content-Type: application/json" \
		-d @kafka-connect/connectors/postgres-source.json | python3 -m json.tool

connector-status: ## Статус коннектора postgres-source-yp5
	curl -s http://localhost:8083/connectors/postgres-source-yp5/status | python3 -m json.tool

connector-delete: ## Удалить коннектор postgres-source-yp5
	curl -s -X DELETE http://localhost:8083/connectors/postgres-source-yp5

# ================== Консьюмер ==================
VENV_DIR := .venv
PYTHON   := $(VENV_DIR)/bin/python
PIP      := $(VENV_DIR)/bin/pip

$(VENV_DIR): consumer/requirements.txt ## Создать venv и установить зависимости (выполняется автоматически)
	@echo "Создаю виртуальное окружение и ставлю зависимости..."
	python3 -m venv $(VENV_DIR)
	$(PIP) install --quiet --upgrade pip
	$(PIP) install --quiet -r consumer/requirements.txt
	@touch $(VENV_DIR)

run-consumer: $(VENV_DIR) ## Запустить консьюмер CDC (venv создаётся и удаляется автоматически)
	$(PYTHON) consumer/cdc_consumer.py; \
	status=$$?; \
	rm -rf $(VENV_DIR); \
	exit $$status

clean-consumer-venv: ## Удалить виртуальное окружение вручную (на случай сбоя)
	rm -rf $(VENV_DIR)
