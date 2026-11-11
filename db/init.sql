-- Создаём базу db_yp5 (если её ещё нет)
-- Файл выполняется от postgres-user, поэтому \c в psql ниже
CREATE DATABASE db_yp5;

-- Подключаемся к новой базе
\c db_yp5;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    product_name VARCHAR(100),
    quantity INT,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
