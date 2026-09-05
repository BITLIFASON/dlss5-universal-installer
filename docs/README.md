# DLSS5 Universal Installer

Переносимая утилита для Windows 10/11 x64. Поддержка игр DX11 и DX12 планируется в первой версии; 32-битные игры будут поддерживаться только там, где выбранный метод имеет отдельный x86/host-компонент.

Запуск: `DLSS5-Universal.cmd`.

Первый режим — `Check only`: он не скачивает, не заменяет и не удаляет файлы. Перед установкой утилита должна показать найденный API, native DLSS и возможные конфликты.

Для автоматизированного запуска доступны команды:

- `src\installer.ps1 -Action Check -GamePath "C:\\Games\\MyGame"` — только анализ игры и JSON manifest;
- `src\installer.ps1 -Action Packages` — список локальных архивов/DLL из `packages` и их SHA-256.
- `src\installer.ps1 -Action Download -SourceId "optiscaler"` — скачивание только зафиксированного HTTPS-релиза после включения `allowAutomaticDownloads` и проверки SHA-256;
- `src\installer.ps1 -Action Bootstrap` — мастер выбора игры и метода: скачивает locked sources, проверяет SHA-256, распаковывает AIO и устанавливает ReShade и выбранный пакет;
- `src\installer.ps1 -Action Install -GamePath "C:\\Games\\MyGame" -PackageManifest "packages\\method.manifest.json"` — проверка, backup и установка перечисленных файлов;
- `src\installer.ps1 -Action Restore` — откат последней установки по manifest.

Пустой каталог `packages` тоже фиксируется manifest-файлом. Скачивание из сети пока намеренно отключено.
Установка принимает только ZIP-архив и manifest с совпадающим SHA-256 архива и хешами каждого файла. Неизвестные файлы не удаляются.
Источники для скачивания фиксируются в `config/sources.lock.json`: URL `latest`, поисковые ссылки и записи без SHA-256 отклоняются.

Профили:

- Native/Bridge — для игр с собственным DLSS;
- OptiScaler — отдельный перехватчик апскейлера;
- ReShade + Feeder — маршрут для игр без native DLSS.

Архивы хранятся только в `packages`. Резервируются конкретные изменяемые файлы, полная копия игры не создаётся.

Общие настройки находятся в `config/settings.json`: язык, поддерживаемые API, обязательное сравнение методов, предупреждение перед повышением прав, порядок поиска локальных пакетов и запрет удаления неизвестных файлов.
