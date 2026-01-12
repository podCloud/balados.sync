# End-to-End (E2E) Testing

This document describes how to set up and run End-to-End tests for Balados Sync using Wallaby.

## Overview

E2E tests run against a real browser (headless Chrome by default) and test the complete application stack including HTML rendering, JavaScript interactions, LiveView components, and navigation flows.

## Prerequisites

### Install ChromeDriver

**macOS:**
```bash
brew install chromedriver
```

**Ubuntu/Debian:**
```bash
apt install chromium-chromedriver
```

**Arch Linux:**
```bash
pacman -S chromedriver
```

### Verify Installation

```bash
chromedriver --version
```

## Running E2E Tests

### Run All E2E Tests

```bash
mix test --include e2e
```

### Watch Browser (Disable Headless Mode)

```bash
WALLABY_HEADLESS=false mix test --include e2e
```

## Writing E2E Tests

### Basic Structure

```elixir
defmodule BaladosSyncWeb.MyFeatureE2ETest do
  use BaladosSyncWeb.E2ECase, async: false

  @moduletag :e2e

  describe "feature" do
    test "does something", %{session: session} do
      session
      |> visit("/path")
      |> fill_in(Query.text_field("Field"), with: "value")
      |> click(Query.button("Submit"))
      |> assert_has(Query.css(".success"))
    end
  end
end
```

### Creating Test Users

```elixir
%{email: email, password: password} = create_test_user()

session
|> visit("/users/log_in")
|> fill_in(Query.text_field("Email"), with: email)
|> fill_in(Query.text_field("Password"), with: password)
|> click(Query.button("Log in"))
```

### Using the Login Helper

```elixir
setup %{session: session} do
  %{email: email, password: password, user: user} = create_test_user()
  session = login(session, email, password)
  {:ok, session: session, user: user}
end
```

## Common Queries

```elixir
Query.css(".my-class")
Query.css("#my-id")
Query.text_field("Label Text")
Query.button("Button Text")
Query.link("Link Text")
Query.css(".item", count: 3)
Query.css(".item", text: "Expected")
```

## Common Actions

```elixir
visit("/path")
fill_in(query, with: "value")
click(query)
assert_has(query)
refute_has(query)
```

## Troubleshooting

### ChromeDriver Not Found

Ensure ChromeDriver is installed and in your PATH.

### Element Not Found

- Verify the element exists on the page
- Check visibility (element might be hidden)
- Use `WALLABY_HEADLESS=false` to debug visually

## Files

- `apps/balados_sync_web/test/support/e2e_case.ex` - Base test case
- `apps/balados_sync_web/test/balados_sync_web/e2e/` - E2E test files
- `config/test.exs` - Wallaby configuration
