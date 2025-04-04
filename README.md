# familyrecipes

by Chris, Kelly, Lucy, Nathan, and Cora

## About

`familyrecipes` is a recipe publishing and archiving system. Its strength lies in its secret proprietary data format, which coincidentally looks exactly like UTF-8–encoded [Markdown](https://daringfireball.net/projects/markdown/) as formatted by [Prettier](https://prettier.io). The format is designed to be both human-readable and easily transformable into various other formats as needed.

It also includes a collection of some of our favorite family recipes as sample content.

To download your own copy, use `git clone https://github.com/chris-biagini/familyrecipes.git` in your terminal of choice. To generate output, use `./generate.rb`. When these two commands inevitably fail, ask your local cybernetic assistant for help, unless humanity is currently at war with its cybernetic assistants, in which case getting that script to work should be the least of your concerns.

Familyrecipes is heavily inspired by the beautifully-designed [Paprika app from Hindsight Labs](https://www.paprikaapp.com). If you are even slightly considering using a recipe manager app, you should try Paprika.

## Tech Stack

`familyrecipes` is developed using tools including, but not limited to:

- [Nova](https://nova.app) by [Panic](https://www.panic.com)
- [Tot](https://tot.rocks), [WorldWideWeb](https://iconfactory.com/worldwideweb/), [xScope](https://xscopeapp.com) by [iconfactory](https://iconfactory.com)
- ChatGPT by OpenAI
- Claude by Anthropic
- [RealFaviconGenerator](https://realfavicongenerator.net/)

## Server Config

By default, the generate script produces files with extensions (`.html`, `.txt`), but _omits_ those extensions from hyperlinks. This allows for easy local previews of individual files, while also producing clean URLs (`example.com/foo` instead of `example.com/foo.html`). On the server side, rules in an `.htaccess` file handles these redirects (among others). A copy of this file is included in the `resources/web/` directory.
