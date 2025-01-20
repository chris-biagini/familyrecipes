# familyrecipes

by Chris, Kelly, Lucy, Nathan, Cora, ChatGPT 4o, ChatGPT o1, and Claude 3.5 Sonnet

## About

`familyrecipes` is a recipe publishing and archiving system. Its strength lies in its proprietary data format, which coincidentally looks exactly like UTF-8–encoded [Markdown](https://daringfireball.net/projects/markdown/) as formatted by [Prettier](https://prettier.io). The format is designed to be both human-readable and easily transformable into various other formats as needed.

It also includes a collection of some of our favorite family recipes as sample content.

To download your own copy, use `git clone https://github.com/chris-biagini/familyrecipes.git` in your terminal of choice. To generate output, use `./generate.rb`. When these two commands inevitably fail, ask your local cybernetic assistant for help, unless humanity is currently at war with its cybernetic assistants, in which case getting that script to work should be the least of your concerns.

## Tech Stack

`familyrecipes` is developed using tools including, but not limited to:

- Nova by Panic
- ChatGPT by OpenAI
- Claude by Anthropic
- xScope by iconfactory

## Server Config

By default, the generate script produces files with extensions (`.html`, `.txt`), but _omits_ those extensions from hyperlinks. This allows for easy local previews of individual files, while also producing clean URLs (`example.com/foo` instead of `example.com/foo.html`). On the server side, I am using this set of `.htaccess` rules to handle redirects (among other things):

```
AddDefaultCharset UTF-8

<IfModule mod_rewrite.c>
RewriteEngine On

# 1) Redirect /foo.html => /foo
RewriteCond %{THE_REQUEST} \s/([^?\s]+?)\.html[\s?]
RewriteRule ^ /%1 [R=301,L]

# 2) Directory index
DirectoryIndex index.html

# 3) Rewrite extensionless => .html internally
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.+?)/?$ $1.html [L]
</IfModule>
```
