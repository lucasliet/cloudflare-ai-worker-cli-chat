# LMChat CLI

Um cliente CLI em bash para interagir com modelos de linguagem locais via API do [lmstudio](lmstudio.ai)

## Requisitos

- `curl`
- `jq`
- Um servidor LLM local do lmstudio rodando na porta 1234 ou qualquer outro servidor em formato compatível com OpenAI

## Instalação

```bash
chmod +x lmchat
sudo mv lmchat /usr/local/bin/
```

## Uso

```bash
lmchat [--model nome-do-modelo] sua mensagem aqui
```

### Opções

- `--model`: Especifica qual modelo usar (padrão: "hermes-3-llama-3.2-3b")

### Exemplo

```bash
lmchat "Qual é a capital do Brasil?"
lmchat --model different-model "Outra pergunta aqui"
```

## Características

- Mantém histórico de conversas em `/tmp/lmchat_messages`
- Suporta streaming de respostas
- Temperatura do modelo configurável (padrão: 0.7)
- Formatação JSON automática das mensagens
- Compatível com a API OpenAI

## Notas Técnicas

- As mensagens são armazenadas no formato ChatGPT (roles: user/assistant)
- Utiliza endpoints compatíveis com OpenAI (`/v1/chat/completions`)
- Requer um servidor LLM local rodando em `http://localhost:1234`
