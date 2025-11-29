# AI Chatbot with Phoenix LiveView & LM Studio

A modern, real-time AI chatbot application built with Phoenix LiveView that connects to LM Studio for local LLM
inference. Features include streaming responses, conversation management, multiple model selection, and export
capabilities.

## Features

- 🔐 **User Authentication** - Secure email/password authentication with session management
- 💬 **Real-time Streaming** - Token-by-token streaming responses from LM Studio
- 📝 **Conversation Management** - Create, view, and delete conversation threads
- 🤖 **Model Selection** - Choose from available LM Studio models
- 📤 **Export Conversations** - Download chats as Markdown or JSON
- 🎨 **Modern UI** - Built with Tailwind CSS and daisyUI components
- 🌓 **Theme Support** - Light and dark theme toggle

## Quick Start with Docker

The fastest way to get started is using Docker:

```bash
# Clone and enter the repository
git clone <repo-url> && cd chatbot

# Create environment file with secrets
cp .env.example .env
openssl rand -base64 48  # Copy output to SECRET_KEY_BASE in .env

# Start the application
docker compose up --build
```

The app will be available at [`http://localhost:4000`](http://localhost:4000).

Make sure both are running on your host machine:

- **LM Studio** at `localhost:1234` (for chat completions)
- **Ollama** at `localhost:11434` (for embeddings)

## Prerequisites

For local development without Docker, ensure you have:

- **Elixir** 1.15 or later
- **Erlang/OTP** 27 or later
- **PostgreSQL** 14 or later (with pgvector extension for memory features)
- **Node.js** (for asset compilation)
- **LM Studio** - Download from [lmstudio.ai](https://lmstudio.ai/) (for chat completions)
- **Ollama** - Download from [ollama.com](https://ollama.com/) (for embeddings)

## Setup Instructions (Local Development)

### 1. Install Dependencies

```bash
mix deps.get
cd assets && npm install
cd ..
```

### 1.5. Setup Pre-commit Hooks (Recommended)

Install [pre-commit](https://pre-commit.com/) to automatically run comprehensive code quality checks before committing:

```bash
# Install pre-commit framework (if not already installed)
# On macOS with Homebrew:
brew install pre-commit

# On other systems:
pip install pre-commit

# Install the git hooks
pre-commit install
```

The pre-commit framework runs these checks automatically:

- **Security audit** - Checks for vulnerable dependencies with `mix hex.audit`
- **Code formatting** - Validates formatting with `mix format`
- **Compilation** - Strict compilation with warnings as errors
- **Static analysis** - Code quality checks with Credo
- **Security scanning** - Phoenix-specific security analysis with Sobelow
- **Tests with coverage** - Full test suite with 10% minimum coverage (goal: 80%)
- **YAML/Markdown linting** - Validates documentation and config files
- **GitHub Actions validation** - Ensures workflow files are valid

You can also run all checks manually:

```bash
# Run all pre-commit hooks
pre-commit run --all-files

# Or use the mix alias
mix precommit

# Or use ex_check for a unified experience
mix check
```

### 2. Configure Database

The default database configuration uses:

- Host: `localhost`
- Username: `postgres`
- Password: `postgres`
- Database: `chatbot_dev`

If you need to change these, edit `config/dev.exs`.

### 3. Create and Migrate Database

```bash
mix ecto.setup
```

This will:

- Create the database
- Run migrations
- Run seeds (if any)

### 4. Setup LM Studio

1. **Download and Install LM Studio**
   - Visit [lmstudio.ai](https://lmstudio.ai/)
   - Download and install for your platform

2. **Download a Model**
   - Open LM Studio
   - Browse the model catalog
   - Download a model (e.g., Llama 2, Mistral, etc.)

3. **Start the Local Server**
   - In LM Studio, go to the "Local Server" tab
   - Load your downloaded model
   - Click "Start Server"
   - The server should start on `http://localhost:1234` by default

4. **Configure LM Studio URL (Optional)**

   If LM Studio is running on a different port, set the environment variable:

   ```bash
   export LM_STUDIO_URL="http://localhost:YOUR_PORT/v1"
   ```

   Or edit `config/dev.exs`:

   ```elixir
   config :chatbot, :lm_studio_url, "http://localhost:YOUR_PORT/v1"
   ```

### 5. Start Phoenix Server

```bash
mix phx.server
```

Or run inside IEx for interactive development:

```bash
iex -S mix phx.server
```

The application will be available at [`http://localhost:4000`](http://localhost:4000)

## Usage

### 1. Register an Account

- Navigate to <http://localhost:4000/register>
- Enter your email and password (minimum 12 characters)
- Click "Create an account"

### 2. Log In

- Navigate to <http://localhost:4000/login>
- Enter your credentials
- Click "Log in"

### 3. Start Chatting

- You'll be redirected to the chat interface at `/chat`
- Select a model from the dropdown (if multiple models are available)
- Type your message in the input field
- Press Send or hit Enter
- Watch as the AI responds in real-time with streaming

### 4. Manage Conversations

- **New Chat**: Click the "New Chat" button in the sidebar
- **Switch Conversations**: Click on any conversation in the sidebar
- **Delete Conversation**: Open a conversation, click "Actions" → "Delete Conversation"

### 5. Export Conversations

- Open a conversation
- Click "Actions" in the header
- Choose "Export as Markdown" or "Export as JSON"
- The file will download automatically

## Project Structure

```text
chatbot/
├── lib/
│   ├── chatbot/
│   │   ├── accounts/          # User authentication
│   │   │   └── user.ex        # User schema
│   │   ├── chat/              # Chat functionality
│   │   │   ├── conversation.ex
│   │   │   └── message.ex
│   │   ├── accounts.ex        # Accounts context
│   │   ├── chat.ex            # Chat context
│   │   ├── lm_studio.ex       # LM Studio API client
│   │   └── repo.ex            # Database repository
│   └── chatbot_web/
│       ├── live/
│       │   ├── auth/          # Authentication LiveViews
│       │   │   ├── login_live.ex
│       │   │   └── registration_live.ex
│       │   └── chat/          # Chat LiveViews
│       │       ├── index.ex   # New conversation
│       │       └── show.ex    # Existing conversation
│       ├── components/        # Reusable components
│       ├── controllers/       # Traditional controllers
│       ├── router.ex          # Route definitions
│       └── user_auth.ex       # Authentication plugs
├── priv/
│   └── repo/
│       └── migrations/        # Database migrations
├── assets/                    # Frontend assets
│   ├── css/
│   └── js/
└── config/                    # Configuration files
```

## Database Schema

The application uses UUIDv7 for all primary keys:

### Users Table

- `id` (binary_id, UUIDv7)
- `email` (string, unique)
- `hashed_password` (string)
- `inserted_at`, `updated_at` (timestamps)

### Conversations Table

- `id` (binary_id, UUIDv7)
- `user_id` (foreign key to users)
- `title` (string)
- `model_name` (string)
- `inserted_at`, `updated_at` (timestamps)

### Messages Table

- `id` (binary_id, UUIDv7)
- `conversation_id` (foreign key to conversations)
- `role` (string: "user", "assistant", "system")
- `content` (text)
- `tokens_used` (integer, nullable)
- `inserted_at`, `updated_at` (timestamps)

## Development

### Running Tests

```bash
mix test
```

### Code Formatting

```bash
mix format
```

### Pre-commit Checks

Run all quality checks before committing:

```bash
# Recommended: Use pre-commit framework (runs all checks)
pre-commit run --all-files

# Or use the mix alias (Elixir checks only)
mix precommit

# Or use ex_check for unified output
mix check
```

The comprehensive check suite includes:

1. **Security audit** - `mix hex.audit` (checks for retired/vulnerable packages)
2. **Code formatting** - `mix format --check-formatted`
3. **Compilation** - `mix compile --warning-as-errors`
4. **Static analysis** - `mix credo --strict` (code quality and consistency)
5. **Security scanning** - `mix sobelow --config` (Phoenix security best practices)
6. **Test coverage** - `mix coveralls` (enforces 10% minimum via coveralls.json; goal: 80%)
7. **Dependency cleanup** - `mix deps.unlock --unused`

Additional tools available:

- **Type checking** - `mix dialyzer` (slower, runs in CI by default)
- **Unused deps** - `mix deps.audit` (finds unused dependencies)

### Database Management

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drop, create, migrate, seed)
mix ecto.reset
```

## Troubleshooting

### LM Studio Connection Issues

#### Error: "Could not connect to LM Studio. Is it running?"

Solutions:

1. Ensure LM Studio is running
2. Verify the local server is started in LM Studio
3. Check that a model is loaded
4. Confirm the server is running on `http://localhost:1234`
5. Check firewall settings

### Database Connection Issues

#### Error: "Connection refused" or "Database does not exist"

Solutions:

1. Ensure PostgreSQL is running
2. Verify credentials in `config/dev.exs`
3. Run `mix ecto.create` to create the database
4. Run `mix ecto.migrate` to apply migrations

### Asset Compilation Issues

#### Error: "esbuild not found" or "tailwind not found"

Solutions:

```bash
mix assets.setup
```

## Configuration

### Environment Variables

- `LM_STUDIO_URL` - LM Studio API endpoint (default: `http://localhost:1234/v1`)
- `PORT` - Phoenix server port (default: `4000`)
- `DATABASE_URL` - PostgreSQL connection string (optional, uses config/dev.exs by default)

### Customizing Themes

The application uses daisyUI themes configured in `assets/css/app.css`. You can customize colors by editing the theme definitions.

## Production Deployment

For production deployment:

1. Set environment variables:

   ```bash
   export SECRET_KEY_BASE="your-secret-key"
   export DATABASE_URL="your-database-url"
   export LM_STUDIO_URL="your-lm-studio-url"
   ```

2. Build assets:

   ```bash
   mix assets.deploy
   ```

3. Run migrations:

   ```bash
   mix ecto.migrate
   ```

4. Start the server:

   ```bash
   mix phx.server
   ```

For more detailed deployment instructions, see the [Phoenix deployment guide](https://hexdocs.pm/phoenix/deployment.html).

## Technology Stack

### Core Application

- **Backend**: Phoenix Framework 1.8, Elixir 1.15
- **Database**: PostgreSQL with Ecto
- **Real-time**: Phoenix LiveView 1.1
- **Authentication**: bcrypt_elixir
- **HTTP Client**: Req
- **Frontend**: Tailwind CSS v4, daisyUI
- **Icons**: Heroicons
- **Markdown**: Earmark
- **Syntax Highlighting**: Makeup

### Code Quality & Development Tools

- **Pre-commit Framework**: Automated git hooks for quality checks
- **Credo**: Static code analysis for Elixir
- **Dialyzer**: Type checking and static analysis
- **Sobelow**: Security-focused static analysis for Phoenix
- **ExCoveralls**: Test coverage tracking (10% minimum enforced; goal: 80%)
- **ex_check**: Unified tool runner for all checks
- **mix_audit**: Dependency auditing

## License

This project is available under the MIT License.

## Learn More

### Phoenix Framework

- Official website: <https://www.phoenixframework.org/>
- Guides: <https://hexdocs.pm/phoenix/overview.html>
- Docs: <https://hexdocs.pm/phoenix>
- Forum: <https://elixirforum.com/c/phoenix-forum>
- Source: <https://github.com/phoenixframework/phoenix>

### LM Studio

- Website: <https://lmstudio.ai/>
- Documentation: <https://lmstudio.ai/docs>

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
