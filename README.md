# Engram Plugin for Claude Code

Persistent memory for Claude Code. Remember decisions, recall past context, and maintain institutional knowledge across sessions.

## Installation

```bash
# Add the marketplace
/plugin marketplace add rawcontext/engram-claude-plugin

# Install the plugin
/plugin install engram@rawcontext-engram
```

## Configuration

Add the Engram MCP server to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "engram": {
      "type": "http",
      "url": "https://mcp.engram.rawcontext.com"
    }
  }
}
```

On first use, you'll be prompted to authenticate via OAuth device flow.

## Commands

### `/engram:prime [task]`

Start a session by loading relevant memories and context.

```
/engram:prime implementing user authentication
/engram:prime refactoring the API layer
/engram:prime
```

### `/engram:recall <query>`

Search memories using semantic similarity.

```
/engram:recall authentication decisions
/engram:recall code style --type=preference
/engram:recall debugging tips --type=insight
```

**Types**: `decision`, `preference`, `insight`, `fact`

### `/engram:remember <content>`

Store information for future sessions.

```
/engram:remember We chose PostgreSQL for its JSON support
/engram:remember Always run tests before pushing --type=preference
/engram:remember The timeout was caused by connection pooling
```

### `/engram:why <topic>`

Find reasoning behind past decisions.

```
/engram:why did we choose React?
/engram:why use tabs over spaces?
/engram:why NATS instead of Kafka?
```

## How It Works

Engram stores memories in a bitemporal graph database with vector embeddings for semantic search. All memories are tagged with time metadata for temporal queries.

**Memory Types**:
- **decision**: Architectural choices with rationale
- **preference**: User conventions and patterns
- **insight**: Debugging discoveries and learnings
- **fact**: Objective information about the codebase

## Automatic Event Ingestion

This plugin includes hooks that automatically capture Claude Code events and forward them to the Engram ingestion service. This provides:

- **Session tracking**: SessionStart/SessionEnd events for session lifecycle
- **Tool usage**: PostToolUse events capture every tool invocation
- **Completion tracking**: Stop events mark agent completion

### Configuration

By default, events are sent to `https://api.engram.rawcontext.com`. Override with:

```bash
# Local development
export ENGRAM_INGESTION_URL="http://localhost:6175"
```

The plugin reads OAuth tokens from `~/.engram/auth.json` (populated by the MCP server's device flow authentication).

### Hook Events

| Event | Description |
|-------|-------------|
| SessionStart | Session initialized with model and tools |
| SessionEnd | Session terminated |
| PostToolUse | Tool executed with inputs and results |
| Stop | Agent completed task |

The hooks run asynchronously in the background and never block Claude Code.

## License

MIT
