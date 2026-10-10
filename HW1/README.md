# TripFund

Сбор средств в ERC-20 с выплатой организатору при достижении цели и возвратами при провале. Реализованы бонус V2 со взносами за других участников, обновление через Transparent Proxy и тесты с проверкой совместимости хранения.

## Установка и тесты

Нужны Foundry 1.8.5 и Node.js 22 или новее. Проект использует Solidity 0.8.30, OpenZeppelin Contracts 5.6.1 и EVM Cancun. Версии остальных зависимостей закреплены в `package-lock.json`.

Из корня репозитория:

```bash
cd HW1
npm ci --ignore-scripts
forge build
forge test
```

`make check` проверяет форматирование, очищает старую сборку и запускает сборку и тесты.

Тесты покрывают взносы, выплаты, границу дедлайна, ошибки переводов и обновление V1 -> V2 с сохранением состояния.

## Локальный пример

В отдельном терминале запустите свежий Anvil:

```bash
anvil --hardfork cancun
```

Дальше - команды для Bash из каталога `HW1`. Используются стандартные разблокированные аккаунты Anvil.

```bash
export RPC_URL=http://127.0.0.1:8545
export ADMIN_OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export ORGANIZER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export FRIEND=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
export GOAL=100000000000000000000
export DURATION=604800

forge script script/TripFund.s.sol:TripFundScript \
  --rpc-url "$RPC_URL" --sender "$ADMIN_OWNER" --unlocked --broadcast
```

Скрипт создаёт токен и прокси, выдаёт администратору 1000 токенов. Цель сбора - 100 токенов, срок - 7 дней. Введите адреса `TOKEN` и `PROXY` из вывода скрипта:

```bash
read -r -p 'TOKEN: ' TOKEN
read -r -p 'PROXY: ' PROXY
export TOKEN PROXY
```

Взнос 40 токенов в V1. `approve` вызывается у токена, получатель разрешения - адрес прокси:

```bash
cast send "$TOKEN" 'approve(address,uint256)' "$PROXY" 40000000000000000000 \
  --from "$ADMIN_OWNER" --unlocked --rpc-url "$RPC_URL"
cast send "$PROXY" 'contribute(uint256)' 40000000000000000000 \
  --from "$ADMIN_OWNER" --unlocked --rpc-url "$RPC_URL"
```

Обновление до V2 и взнос 25 токенов за друга:

```bash
forge script script/TripFund.s.sol:TripFundScript --sig 'upgrade()' \
  --rpc-url "$RPC_URL" --sender "$ADMIN_OWNER" --unlocked --broadcast

cast send "$TOKEN" 'approve(address,uint256)' "$PROXY" 25000000000000000000 \
  --from "$ADMIN_OWNER" --unlocked --rpc-url "$RPC_URL"
cast send "$PROXY" 'contributeFor(address,uint256)' "$FRIEND" 25000000000000000000 \
  --from "$ADMIN_OWNER" --unlocked --rpc-url "$RPC_URL"
```

Собрано 65 токенов из 100. После дедлайна можно вернуть оба вклада:

```bash
cast rpc evm_increaseTime 604800 --rpc-url "$RPC_URL"
cast rpc evm_mine --rpc-url "$RPC_URL"

cast send "$PROXY" 'refund()' --from "$ADMIN_OWNER" --unlocked --rpc-url "$RPC_URL"
cast send "$PROXY" 'refund()' --from "$FRIEND" --unlocked --rpc-url "$RPC_URL"
```

У плательщика останется 975 токенов, у друга будет 25. `totalRaised` останется равным 65 токенам: это сумма всех принятых взносов, она не уменьшается после выплат.

Прямые переводы токенов на прокси не считаются взносами и не возвращаются. `TestToken` имеет 18 десятичных знаков и открытый `mint`; он предназначен для локальных тестов. Скрипт развёртывания работает только в сети с chain ID 31337.
