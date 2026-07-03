# linux-ss-scripts

Bash-скрипты для PC Check Minecraft на Linux. Запуск на ПК подозреваемого через `curl`.

## Команды

```bash
BASE=https://raw.githubusercontent.com/greshnobytela-dotcom/linux-ss-scripts/main

# Mods
bash -c "$(curl -fsSL $BASE/mod-analyzer.sh)"

# Doomsday
bash -c "$(curl -fsSL $BASE/doomsday-detector.sh)"

# INJGEN (inject)
bash -c "$(curl -fsSL $BASE/injgen-linux.sh)"

# JNI
bash -c "$(curl -fsSL $BASE/jni-check.sh)"

# BrowserHistory (URL/IP читов)
bash -c "$(curl -fsSL $BASE/browser-history.sh)"

# AllDownloads (все скачивания)
bash -c "$(curl -fsSL $BASE/all-downloads.sh)"

# System info
bash -c "$(curl -fsSL $BASE/sysinfo.sh)"

# Обёртка
curl -fsSL $BASE/run.sh | bash -s -- mods
curl -fsSL $BASE/run.sh | bash -s -- browser
curl -fsSL $BASE/run.sh | bash -s -- downloads
```

## Файлы

| Скрипт | Назначение |
|:--|:--|
| `mod-analyzer.sh` | Modrinth + cheat strings в mods |
| `doomsday-detector.sh` | Следы Doomsday |
| `injgen-linux.sh` | JNI/javaagent inject (как InjGen) |
| `jni-check.sh` | Ghost jar + .so кратко |
| `browser-history.sh` | URL/IP читов в браузере |
| `all-downloads.sh` | Таблица всех скачиваний |
| `sysinfo.sh` | Дистрибутив, VM, дата установки |
| `common-dirs-scan.sh` | Jar в типичных папках |
| `memory-search.sh` | gcore/strings обёртка |
| `run.sh` | `mods\|doomsday\|jni\|inj\|browser\|downloads\|sys\|scan` |
