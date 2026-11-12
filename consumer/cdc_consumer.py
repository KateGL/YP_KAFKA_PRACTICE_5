#!/usr/bin/env python3
"""Консьюмер CDC: читает Debezium-события из топиков users/orders и печатает их."""
import json
import sys
from kafka import KafkaConsumer
import logging
logging.basicConfig(level=logging.INFO)


BOOTSTRAP_SERVERS = ["localhost:29092", "localhost:29093", "localhost:29094"]
TOPICS = ["yp5.public.users", "yp5.public.orders"]
GROUP_ID = "cdc-terminal-viewer-20000"


OP_LABELS = {
    "c": "CREATE",
    "u": "UPDATE",
    "d": "DELETE",
    "r": "SNAPSHOT",  # событие начального снапшота
}


def format_row(row: dict | None) -> str:
    if row is None:
        return "нет"
    return ", ".join(f"{k}={v}" for k, v in row.items() if k != "__deleted")


def process_message(topic: str, data: dict | None) -> None:
    if data is None:
        return  # tombstone
    # JsonConverter оборачивает событие в {"schema": ..., "payload": {...}}
    payload = data.get("payload", data)
    op = payload.get("op")
    if op is None:
        return

    table = payload.get("source", {}).get("table", "?")
    op_label = OP_LABELS.get(op, op)

    if op == "d":
        change = f"BEFORE: {format_row(payload.get('before'))}"
    elif op == "u":
        change = (
            f"BEFORE: {format_row(payload.get('before'))}\n"
            f"        AFTER:  {format_row(payload.get('after'))}"
        )
    else:
        change = f"ROW: {format_row(payload.get('after'))}"

    print(f"[{table}] {op_label}")
    print(f"        {change}")
    print("-" * 60)


def main() -> None:
    consumer = KafkaConsumer(
        *TOPICS,
        bootstrap_servers=BOOTSTRAP_SERVERS,
        group_id=GROUP_ID,
        auto_offset_reset="earliest",
        enable_auto_commit=True,
        value_deserializer=lambda b: json.loads(b) if b is not None else None,
        consumer_timeout_ms=1000,  # чтобы Ctrl+C не зависал в неудобный момент
    )

    print(f"Подписан на {TOPICS}, bootstrap: {BOOTSTRAP_SERVERS}")
    print("Ожидаю сообщения... (Ctrl+C для выхода)")
    print("=" * 60)

    try:
        while True:
            batch = consumer.poll(timeout_ms=1000)
            for tp, records in batch.items():
                for record in records:
                    process_message(tp.topic, record.value)
    except KeyboardInterrupt:
        print("\nОстановлено пользователем.")
    finally:
        consumer.close()
        sys.exit(0)


if __name__ == "__main__":
    main()
