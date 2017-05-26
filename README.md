# Интеграция OTRS c Asterisk

* OTRS должен использовать MySQL базу данных
* gem install mysql2
* Настроить скрипт для работы в текущей среде:
```ruby
  # Имя хоста базы данных OTRS
  DB_HOST = "<OTRS DB_IP>"
  # Имя пользователя базы данных
  DB_USER = "<OTRS DB_USER>"
  # Название базы
  DB_NAME = "<OTRS DB_NAME>"
  # Пароль пользователя базы данных
  DB_PASSWORD = "<OTRS DB_PASSWORD>"
  # Имя агента OTRS
  OTRS_USER = '<OTRS USER>'
  # Пароль агента OTRS
  OTRS_PASS = '<OTRS PASS>'
  # URL OTRS для REST API, например http://localhost/otrs/nph-genericinterface.pl/Webservice 
  OTRS_REST_URL = '<OTRS REST URL>'
  # URI для REST API, в документации по OTRS в разделе создания REST API сервисов об этом написано,
  # например /CreateTicket/New
  OTRS_REST_URI_CREATE_TICKET = '<OTRS REST URI>'
  # Номера телефонов, с которых будет игнорироваться создания тикетов
  # указывать через пробел
  IGNORE_PHONES = %w()
  # полный путь до файла логов
  LOG_FILE = '<OTRS LOGFILE>'
```
В настройках экстеншенов Asterisk надо передавать в скрипт 1 аргумент - внутренний номер агента
```
    h => {
        AGI(create_ticket.rb,${CONNECTEDLINE(num)});
        HangUp();
    };
```
