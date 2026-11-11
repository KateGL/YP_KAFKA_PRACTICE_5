#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${1:-db_yp5}"
USER="postgres-user"
# Сколько тестовых пользователей и заказов создать
USERS_COUNT="${2:-10}"
ORDERS_PER_USER="${3:-3}"

echo "Наполняю базу ${DB_NAME}: ${USERS_COUNT} пользователей, по ${ORDERS_PER_USER} заказов каждому..."

docker exec -i postgres psql -U "${USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<SQL
-- Очищаем таблицы (порядок важен из-за внешнего ключа)
TRUNCATE orders, users RESTART IDENTITY;

-- Генерируем пользователей: Иван Иванович_1, Иван Иванович_2...
INSERT INTO users (name, email, created_at)
SELECT
    'Иван Иванович_' || g,
    'user_' || g || '@example.com',
    NOW() - (g || ' days')::interval
FROM generate_series(1, ${USERS_COUNT}) AS g;

-- Генерируем заказы: каждому пользователю по ORDERS_PER_USER заказов
-- на случайные товары и в случайном количестве
INSERT INTO orders (user_id, product_name, quantity, order_date)
SELECT
    u.id,
    (ARRAY['ноутбук', 'мышка', 'клавиатура', 'монитор', 'наушники', 'SSD 1TB'])[1 + floor(random() * 6)::int],
    1 + floor(random() * 5)::int,
    NOW() - (floor(random() * 30) || ' days')::interval
FROM users u
CROSS JOIN generate_series(1, ${ORDERS_PER_USER});
SQL

echo "Готово. Итог:"
docker exec -i postgres psql -U "${USER}" -d "${DB_NAME}" -c \
  "SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM orders) AS orders;"
