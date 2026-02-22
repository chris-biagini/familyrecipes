# familyrecipes

_recipes by Chris, Kelly, Lucy, Nathan, and Cora_
_code by Chris, ChatGPT, and Claude_

## About

`familyrecipes` is a recipe publishing and archiving system built with Ruby on Rails. Recipes are authored in Markdown and stored in a PostgreSQL database. The app supports multi-tenant "Kitchens" with web-based editing for recipes, Quick Bites, and grocery aisles.

The project includes a collection of our favorite family recipes as seed data.

The functionality of `familyrecipes` is heavily inspired by the beautifully-designed [Paprika app from Hindsight Labs](https://www.paprikaapp.com). If you are considering using a recipe manager app, you should try Paprika.

## Getting Started

```bash
bundle install
rails db:create db:migrate db:seed
bin/dev
```

This starts the app on `http://localhost:3030`. Seed data is loaded from `db/seeds/` — recipe markdown files, grocery aisle mappings, nutrition data, and site configuration.

## Tech Stack

- [Ruby on Rails 8](https://rubyonrails.org/) with [PostgreSQL](https://www.postgresql.org/)
- [Nova](https://nova.app) by [Panic](https://www.panic.com)
- [ChatGPT](https://chatgpt.com/) by [OpenAI](https://openai.com/)
- [Claude](https://claude.ai/) by [Anthropic](https://www.anthropic.com/)
- [RealFaviconGenerator](https://realfavicongenerator.net/)
