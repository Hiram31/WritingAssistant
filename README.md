# WritingAssistant ✍️

WritingAssistant is a PopClip-style AI writing palette for macOS.

Select text in Gmail, Slack, a browser, an editor, or a document. A compact floating popup appears near your selection, ready to fix grammar, tune tone, polish academic writing, run your own prompt, or draft brand-new text and paste it back into the app you were already using.

## ⚡ How It Feels

1. Select text anywhere you write.
2. A small floating palette appears next to the selection.
3. Click `Fix`, `Sup`, `Par`, `Flu`, `Acd`, or one of your own custom styles.
4. WritingAssistant sends the request to your selected AI provider.
5. The selected text is replaced in place, or a new draft is pasted where your cursor was.

## 🎬 Demo

<video src="assets/demo.mp4" controls muted playsinline width="100%"></video>

[Download the demo video](assets/demo.mp4)

## ✨ Highlights

- 🫧 **PopClip-style floating popup**: quick actions appear near selected text, without opening a full chat window.
- 📝 **One-click cleanup**: fix grammar, spelling, punctuation, clarity, and awkward phrasing.
- 🎩 **Tone-specific rewrites**: switch between supervisor-ready, partner-facing, coworker-chat, and academic styles.
- 🎓 **Academic polish**: tune reviewer comments, author responses, rebuttal letters, manuscript text, and editor communication.
- 🧩 **Custom writing styles**: add, remove, enable, disable, and edit your own prompt-driven buttons.
- 🪄 **Draft composer**: type `compose an email asking the supplier for status` and paste a complete draft into the current app.
- 🧠 **Prompt control**: edit every built-in tune plus the draft composer prompt from Settings.
- 🤖 **Provider choice**: use Azure OpenAI, local Ollama, OpenAI-style APIs, Anthropic, Gemini, Cohere, and other gateways.
- ⌨️ **Global hotkeys**: open the draft composer, force the selection popup, or open Settings from anywhere.
- 🧯 **Less annoying by design**: popup delay, cooldown, selection thresholds, repeat suppression, Esc-to-dismiss, and placement controls keep it from getting in your way.
- 🔐 **Local-first settings**: API keys stay in macOS Keychain, while prompts and behavior controls stay in app preferences.

## 🎯 Good For

- Turning rough Slack notes into clear coworker messages.
- Making status updates more professional before sending them to a supervisor.
- Rewriting client or partner-facing updates with a polished tone.
- Cleaning up email drafts directly inside Gmail or another mail app.
- Drafting quick replies without switching to a separate AI chat tab.
- Polishing academic review comments, rebuttal language, and manuscript paragraphs.
- Running your own reusable writing prompts from a tiny popup.

## ✅ Requirements

- macOS 13 or newer
- Xcode command line tools
- One AI backend:
  - Azure OpenAI
  - Local Ollama
  - Custom AI provider

## 🚀 Run

```sh
swift run WritingAssistant
```

On first launch, click the WritingAssistant menu bar icon, choose `Settings...`, then configure the `AI` tab.

## 🤖 AI Providers

WritingAssistant keeps the provider list intentionally simple:

- `Azure OpenAI`
- `Ollama`
- `Custom AI provider`

### Azure OpenAI

Use this when you have an Azure OpenAI resource and deployment.

Recommended starting values:

- `Base URL`: `https://your-resource.openai.azure.com/`
- `Model / deployment`: your Azure deployment name, for example `gpt-5.4-mini`
- `Azure API version`: `2024-10-21`
- `API key`: your Azure OpenAI key

Azure uses the deployment endpoint:

```text
/openai/deployments/{deployment}/chat/completions?api-version={apiVersion}
```

### Ollama

Use this for local models running through Ollama.

Recommended starting values:

- `Base URL`: `http://localhost:11434/api`
- `Model / deployment`: your local model name, for example `gemma3:1b`
- `API key`: leave empty

Example local model setup:

```sh
ollama pull gemma3:4b
```

WritingAssistant uses Ollama's native `/api/generate` endpoint with `"stream": false`, matching this style:

```sh
curl http://localhost:11434/api/generate -d '{
  "model": "gemma3:4b",
  "prompt": "Why is the sky blue?",
  "stream": false
}'
```

### Custom AI Provider

Use this when your provider is not Azure or Ollama. Choose an `API format` first, then enter the provider's API key, Base URL, and model name.

#### OpenAI-style Chat Completions

Use this for APIs that follow the Chat Completions request and response shape: `messages`, `model`, and a `choices[0].message.content` response.

Good starting Base URLs:

| Provider | Base URL | Example model |
| --- | --- | --- |
| OpenAI | `https://api.openai.com` | `gpt-4o-mini` |
| OpenRouter | `https://openrouter.ai/api/v1` | `openai/gpt-4o-mini` |
| Groq | `https://api.groq.com/openai/v1` | `llama-3.3-70b-versatile` |
| Mistral AI | `https://api.mistral.ai/v1` | `mistral-small-latest` |
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat` |
| xAI | `https://api.x.ai/v1` | `grok-4.20-reasoning` |
| Together AI | `https://api.together.xyz/v1` | `meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo` |
| Local LM Studio / vLLM / LiteLLM | `http://localhost:1234/v1` | your local model name |

WritingAssistant appends `/chat/completions` automatically. For OpenAI, you can enter `https://api.openai.com`; the app calls `https://api.openai.com/v1/chat/completions`.

#### Anthropic Messages

Use this for Claude's native Messages API.

- `Base URL`: `https://api.anthropic.com`
- `Model / deployment`: for example `claude-sonnet-4-5`
- The app calls `/v1/messages`
- Auth headers: `x-api-key` and `anthropic-version: 2023-06-01`

#### Gemini GenerateContent

Use this for Google's native Gemini API. Do not use the old Gemini OpenAI-compatibility URL here.

- `Base URL`: `https://generativelanguage.googleapis.com`
- `Model / deployment`: for example `gemini-2.5-flash`
- The app calls `/v1beta/models/{model}:generateContent`
- Auth header: `x-goog-api-key`

#### Cohere Chat

Use this for Cohere's native v2 Chat API.

- `Base URL`: `https://api.cohere.com`
- `Model / deployment`: for example `command-r` or `command-a-03-2025`
- The app calls `/v2/chat`
- Auth header: `Authorization: Bearer <key>`

Provider docs checked while wiring these formats:

- [OpenAI Chat Completions](https://platform.openai.com/docs/api-reference/chat/create)
- [Anthropic Messages API](https://docs.anthropic.com/en/api/messages-examples)
- [Gemini GenerateContent API](https://ai.google.dev/api/generate-content)
- [Cohere Chat API](https://docs.cohere.com/v2/reference/chat)
- [OpenRouter Chat Completions](https://openrouter.ai/docs/api-reference/chat-completion)
- [Groq OpenAI compatibility](https://console.groq.com/docs/openai)
- [Mistral Chat Completions](https://docs.mistral.ai/api/)
- [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)
- [xAI Chat Completions](https://docs.x.ai/docs/guides/chat-completions)
- [Together AI Chat Completions](https://docs.together.ai/reference)

## ⚙️ Settings Tabs

The settings window is split into tabs so the app is easier to configure.

- `AI`: provider, Custom API format when relevant, API key, Base URL, model/deployment, Azure API version when relevant, max output tokens, and `Test Provider`.
- `Popup`: popup timing, cooldown, size, position, offsets, selection thresholds, and keyboard-selection behavior.
- `Hotkeys`: enable global hotkeys and record shortcuts by clicking the field and pressing keys.
- `Replacement`: paste-first or Accessibility-then-paste replacement strategy, paste delay, and clipboard restore timing.
- `Logs`: log folder, verbose monitor logs, and optional selected-text previews.
- `Prompts`: edit built-in prompts, tune the draft composer prompt, hide default tunes, and add/remove custom styles.

Changes apply after clicking `Save Settings`. Selection monitors and hotkeys reload automatically.

## 🔐 Privacy And Secrets

API keys are stored in macOS Keychain. Provider choice, Base URL, model name, prompts, popup behavior, and other non-secret preferences are stored in app preferences.

By default, logs include text length and word count, not the selected text itself. Selected-text previews are opt-in from `Settings... -> Logs`.

## 🛡️ macOS Permissions

WritingAssistant needs Accessibility permission to read selected text and paste the generated result back into the active app.

Open:

```text
System Settings -> Privacy & Security -> Accessibility
```

If you run with `swift run WritingAssistant`, enable the launcher app in Accessibility settings. This is usually Terminal, iTerm, VS Code, Xcode, or the built `WritingAssistant` executable.

The menu bar icon includes:

- `Request Accessibility Permission`: asks macOS to show the permission prompt. macOS may ignore this if it already made a decision.
- `Open Accessibility Settings`: opens the reliable manual settings page.

Restart WritingAssistant after changing Accessibility permission.

## 🧭 Basic Usage

1. Start the app with `swift run WritingAssistant`.
2. Configure an AI provider from the menu bar icon: `Settings... -> AI`.
3. Select text in any editable app.
4. Click one of the floating popup actions.
5. WritingAssistant replaces the selected text with the generated result.

Floating popup actions:

- `Fix`: grammar, spelling, punctuation, and clarity.
- `Sup`: formal rewrite from an employee to a supervisor.
- `Par`: formal rewrite from a client or business contact to external partners.
- `Flu`: natural daily coworker chat.
- `Acd`: academic journal review comments, author responses, manuscript text, or editor/author communication.
- Custom styles: add your own name, short popup label, and prompt in `Settings... -> Prompts -> + Add Style`.

Default tunes can be removed from the popup by unchecking `Show in popup` beside that prompt in `Settings... -> Prompts`. The prompt text remains saved, so you can re-enable it later.

## 🪄 Draft Composer

Use draft mode when you want new text instead of rewriting selected text.

1. Click where the new text should be inserted, for example in a Gmail compose window.
2. Open `New Draft...` from the menu bar icon, or use the draft hotkey.
3. Type a request in the draft field, for example `compose an email to ask the status from the supplier`.
4. Press Return or click the send button.
5. WritingAssistant generates the draft and pastes it into the app that was active when you opened the composer.

The same draft field also appears above the rewrite buttons in the normal popup.
Tune draft behavior from `Settings... -> Prompts -> Draft composer`.

## ⌨️ Hotkeys

Default global hotkeys:

- `Ctrl+Opt+Cmd+D`: open the draft composer.
- `Ctrl+Opt+Cmd+R`: read the current selection and show the rewrite popup.
- `Ctrl+Opt+Cmd+,`: open settings.

Change them in `Settings... -> Hotkeys`:

1. Click a shortcut field.
2. Press the new key combination.
3. Press Delete while the field is focused to clear it.
4. Click `Save Settings`.

WritingAssistant registers hotkeys as system hotkeys, so the frontmost app should not beep when you press them. If registration fails, choose a shortcut that is not reserved by macOS or another app.

The menu bar shortcuts for `New Draft...` and `Settings...` follow the values saved in the Hotkeys tab.

## 🫧 Popup Behavior

The popup is intentionally conservative by default:

- Plain one-click cursor movement is ignored.
- Tiny mouse drags are ignored to avoid accidental clipboard checks and system beeps.
- Mouse selection requires a real drag distance before the app tries to read selected text.
- Double/triple-click selection can trigger the popup.
- It waits briefly after selection before showing.
- It cancels a pending popup if you keep interacting.
- It ignores very short selections.
- It ignores short single-word selections.
- It suppresses repeated popups for the same selected text.
- It auto-hides after a delay.
- Press `Esc` to dismiss it immediately.

Tune these in `Settings... -> Popup`, including panel scale, anchor position, X/Y offsets, selection length limits, read delay, show delay, cooldown, repeat suppression, and auto-hide.

## 📋 Replacement Behavior

Paste is the default replacement strategy because apps such as Slack can report Accessibility replacement success without actually changing text.

Replacement options:

- `Paste`: activates the source app and pastes the generated text.
- `Accessibility, then paste`: tries direct Accessibility replacement first, then falls back to paste.

Clipboard behavior:

- WritingAssistant snapshots the current clipboard before paste fallback.
- It temporarily places the generated result on the clipboard.
- It restores the previous clipboard after the configured delay.

Adjust this in `Settings... -> Replacement`.

## 🪵 Logs

Runtime logs are written to Terminal when you launch with `swift run WritingAssistant`, and also to:

```sh
~/Library/Logs/WritingAssistant/writing-assistant.log
```

Open logs from:

```text
Menu bar icon -> Open Log Folder
```

Watch logs live:

```sh
tail -f ~/Library/Logs/WritingAssistant/writing-assistant.log
```

Logs help debug selection reading, provider requests, replacement, hotkey registration, and popup behavior.

## 🧯 Troubleshooting

### Popup appears too often

Increase these in `Settings... -> Popup`:

- `Read delay`
- `Show delay`
- `Cooldown`
- `Repeat suppression`
- `Minimum chars`
- `Single-word minimum`

You can also leave keyboard-selection support off to reduce interruptions.

## 📌 Notes

- API keys should stay in Keychain. Do not put them in source code.
- Selected-text previews in logs are disabled by default for privacy.
- Custom prompts can strongly affect output quality. Keep prompts specific and tell the model to return only the final text.
