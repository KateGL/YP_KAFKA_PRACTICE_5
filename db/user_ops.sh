#!/usr/bin/env bash
set -euo pipefail

DB_NAME="db_yp5"
USER="postgres-user"

# Безопасное экранирование одинарных кавычек в SQL-литерале
sql_escape() {
    echo "'${1//\'/\'\'}'"
}

run() {
    docker exec -i postgres psql -U "${USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "$1"
}

case "${1:-}" in
    delete-order)
        ID="${2:?Использование: $0 delete-order <id>}"
        run "DELETE FROM orders WHERE id = ${ID};"
        echo "Заказ ${ID} удалён (если существовал)."
        ;;

    delete-user)
        ID="${2:?Использование: $0 delete-user <id>}"
        run "DELETE FROM users WHERE id = ${ID};"
        echo "Пользователь ${ID} удалён (если существовал)."
        ;;

    update-user)
        ID="${2:?Использование: $0 update-user <id> (имена полей передаются через NAME= и EMAIL=)}"
        shift 2

        SET_SQL=()
        if [ -n "${NAME:-}" ]; then
            SET_SQL+=("name = $(sql_escape "${NAME}")")
        fi
        if [ -n "${EMAIL:-}" ]; then
            SET_SQL+=("email = $(sql_escape "${EMAIL}")")
        fi
        if [ "${#SET_SQL[@]}" -eq 0 ]; then
            echo "Нечего обновлять. Укажите NAME и/или EMAIL."
            exit 1
        fi

        SET_CLAUSE=$(IFS=", "; echo "${SET_SQL[*]}")
        run "UPDATE users SET ${SET_CLAUSE} WHERE id = ${ID};"
        run "SELECT id, name, email FROM users WHERE id = ${ID};"
        ;;

    *)
        echo "Использование: $0 {delete-order <id> | delete-user <id> | update-user <id> [name=...] [email=...]}"
        exit 1
        ;;
esac
