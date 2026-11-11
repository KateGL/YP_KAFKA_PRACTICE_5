# YP_KAFKA_PRACTICE_5

Как пользоваться makefile
make help          # список всех команд с описанием
make up            # поднять стек
make health        # убедиться, что всё готово
make ps            # статус
make logs          # смотреть логи
make down          # остановить (данные сохранятся)
make clean         # снести всё вместе с томами


make init-db

make connector-create
make connector-status

make seed-db
make delete-order ID=5
make delete-user ID=3
make update-user ID=3 NAME="Мария Сергеевна"
make update-user ID=3 EMAIL=maria@example.com
make update-user ID=3 NAME="Мария С." EMAIL=maria@example.com   # оба поля сразу

