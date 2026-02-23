# How Your Rails App Works

You built the recipe parser. You know `LineClassifier`, `RecipeBuilder`, `IngredientParser` inside and out. You wrote `FamilyRecipes::Recipe`, `FamilyRecipes::Step`, `FamilyRecipes::Ingredient` — the classes that turn a Markdown file into structured Ruby objects.

This tutorial shows you what Rails does with those objects.

It is not a Rails course. It won't teach you to write controllers or configure routes. It's a guided tour of *your* app — the one wrapped around your parser — so you can have informed conversations with Claude about how it works, why things are where they are, and what to ask for when you want something changed.

**You don't need to memorize any of this.** The point is to build a mental model: a sense of which pieces exist, what they're called, and roughly how they connect. When you're talking to Claude about a feature or a bug, knowing the right word — "controller," "migration," "concern" — gets you to the answer faster. If you forget the details, just point Claude at this document.

## How to read this

The tutorial follows two stories through the codebase. Each one traces a real HTTP request from the moment it hits the server to the moment the browser gets a response.

### Table of Contents

**[Journey 1: Someone reads your Focaccia recipe](#journey-1-someone-reads-your-focaccia-recipe)**
A visitor types in a URL and gets a recipe page. This is the *read path* — a GET request that flows through routing, a controller, the database, and a view template. By the end you'll understand how a URL becomes an HTML page, and where your parser's output lives in the database.

**[Journey 2: Someone edits and saves that recipe](#journey-2-someone-edits-and-saves-that-recipe)**
A logged-in family member opens the recipe editor, changes an ingredient, and hits save. This is the *write path* — a PATCH request that goes through authentication, validation, your parser (yes, it runs again here), and the database import pipeline. By the end you'll understand how the app protects data, when your code runs, and how edits flow back into the database.

**[Glossary](#glossary)**
A reference list of Rails terms used in this tutorial — routes, controllers, models, migrations, concerns, and the rest — defined in the context of your app, not in the abstract.

---

### A word about the app itself

This is a Rails 8 application backed by PostgreSQL. It runs on a single server (Puma) with no background job queue, no JavaScript framework, and no build step. Recipes are authored in Markdown, parsed by your code at save time, and stored as structured rows in the database. Every page renders live from those rows — there is no static site generator.

The app supports multiple "Kitchens" (think of them as separate family cookbooks that share the same server), and uses OmniAuth for login. All recipe data is scoped to a Kitchen, so one family's recipes never leak into another's.

If you run `bin/dev`, the server starts on port 3030 and you can see it at `http://localhost:3030`.

---

*Let's start with the read path.*
