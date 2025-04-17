# Cloudflare AI Worker Chat CLI

Um cliente CLI em bash para interagir com modelos de linguagem via Cloudflare AI Workers

## Requisitos

- `curl`
- `jq`
- Uma conta Cloudflare com acesso aos AI Workers
- Token de autenticação do Cloudflare
- ID da conta Cloudflare

## Configuração

1. Configure as variáveis de ambiente:
```bash
export CLOUDFLARE_AUTH_TOKEN="seu-token-aqui"
export CLOUDFLARE_ACCOUNT_ID="seu-account-id-aqui"
```

2. Instale o script:
```bash
chmod +x llama
sudo mv llama /usr/local/bin/
```

## Uso

```bash
llama [--model nome-do-modelo] sua mensagem aqui
```

### Opções

- `--model`: Especifica qual modelo usar (padrão: "@cf/meta/llama-3.3-70b-instruct-fp8-fast")

### Exemplo

```bash
llama escreva um poema
llama "Qual é a capital do Brasil?"
llama --model @cf/meta/llama-3.3-70b-instruct "qual sua opinião sobre IA?"
```

## Características

- Mantém histórico de conversas em `/tmp/llamachat_messages`
- Suporta streaming de respostas
- Temperatura do modelo configurável (padrão: 0.7)
- Formatação JSON automática das mensagens
- Integração com Cloudflare AI Workers

## Modelos Disponíveis
https://developers.cloudflare.com/workers-ai/models/

## Notas Técnicas

- As mensagens são armazenadas no formato ChatGPT (roles: user/assistant)
- Utiliza a API do Cloudflare AI Workers
- Requer autenticação via token do Cloudflare
