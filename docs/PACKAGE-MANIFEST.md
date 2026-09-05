# Локальные пакеты

Установка будет разрешена только для пакета, который заранее находится в `packages` и описан проверяемым manifest-файлом. Минимальная схема:

```json
{
  "id": "example-method",
  "version": "1.0.0",
  "method": "OptiScaler",
  "archive": "example-method.zip",
  "installRelativeTo": "primaryExecutableDirectory",
  "sha256": "<sha256 архива>",
  "source": "https://официальный-источник/релиз",
  "files": [
    { "path": "dxgi.dll", "sourcePath": "OptiScaler.dll", "sha256": "<sha256 файла после распаковки>" }
  ]
}
```

`path` — имя назначения в папке игры. Необязательный `sourcePath` — имя файла внутри архива; это позволяет, например, безопасно установить `OptiScaler.dll` как `dxgi.dll` после явного указания в manifest.

`source` нужен для аудита происхождения. Публичный архив сам по себе не является доказательством безопасности. До появления такого manifest-файла утилита может только показать инвентарь и хеши, но не устанавливает пакет.

Для автоматической загрузки используется отдельный `config/sources.lock.json`. В нём должны быть конкретные версии, HTTPS URL release asset и ожидаемый SHA-256. Поле `allowAutomaticDownloads` в `config/settings.json` по умолчанию выключено.
