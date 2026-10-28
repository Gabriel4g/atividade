# Web Crawler Eleições 2026 - Refatoração XP

Este projeto é uma evolução de um script em Shell Script para consulta de resultados do TSE, modificado em dupla através de Pair Programming e princípios do Manifesto Ágil.

## Objetivo
Compreender o código existente e implementar melhorias incrementais (municípios do MA, turnos e identificação de eleitos) mantendo a simplicidade e a legibilidade do código.

## Pré-requisitos
* Terminal Bash (Linux/macOS/WSL)
* `curl`
* `jq`

## Como Executar e Exemplos de Uso
O script pesquisa o estado do Maranhão por predefinição. Pode ser executado diretamente através do terminal, alterando as variáveis de ambiente necessárias.

**Pesquisar no Maranhão inteiro (1.º Turno):**
```bash
TSE_RESULTS_TURNO=1 TSE_RESULTS_MUNICIPALITY="" ./buscador.sh