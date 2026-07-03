#!/usr/bin/env bash
# Старый URL — редирект (CDN кешировал меню-версию)
exec bash <(curl -fsSL "https://raw.githubusercontent.com/greshnobytela-dotcom/linux-ss-scripts/main/injgen-linux.sh") "$@"
