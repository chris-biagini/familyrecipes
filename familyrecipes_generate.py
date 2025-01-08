#!/usr/bin/env python3

import re
import sys
import shutil
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass
import jinja2
import markdown

@dataclass
class Ingredient:
    name: str
    quantity: Optional[str] = None
    prep_note: Optional[str] = None

@dataclass
class Section:
    title: str
    ingredients: Optional[List[Ingredient]] = None
    instructions: str = ""

def transform_filename(filename: str) -> str:
    """Transform a filename into a standardized recipe ID format.
    
    Args:
        filename: The original filename (with or without extension)
        
    Returns:
        A lowercase string with spaces replaced by hyphens
    """
    # Remove extension if present
    base = Path(filename).stem
    # Convert to lowercase and replace spaces with hyphens
    # Also collapse multiple spaces/hyphens into a single hyphen
    return re.sub(r'[-\s]+', '-', base.lower())

def markdown_to_html(text: str) -> str:
    """Convert Markdown to HTML using python-markdown."""
    return markdown.markdown(text)

def parse_ingredient(line: str) -> Ingredient:
    """Parse an ingredient line into name, quantity, and prep note."""
    # Remove leading bullet point if present
    line = re.sub(r'^\s*[\*\-]\s*', '', line)
    
    # Split into parts
    parts = line.split(':', 1)
    main_part = parts[0].strip()
    prep_note = parts[1].strip() if len(parts) > 1 else None
    
    # Split main part into name and quantity
    name_qty = main_part.split(',', 1)
    name = name_qty[0].strip()
    quantity = name_qty[1].strip() if len(name_qty) > 1 else None
    
    return Ingredient(name=name, quantity=quantity, prep_note=prep_note)

def parse_markdown_file(file_path: Path) -> Dict:
    """Parse a Markdown recipe file into structured data."""
    content = file_path.read_text()
    lines = content.split('\n')
    
    # Find the title (first non-empty line)
    title = None
    current_line = 0
    while current_line < len(lines) and not title:
        if lines[current_line].strip():
            title = lines[current_line].strip()
            # Handle Setext-style headers
            if current_line + 1 < len(lines) and re.match(r'^=+$', lines[current_line + 1].strip()):
                current_line += 1
            # Handle ATX-style headers
            else:
                title = re.sub(r'^#+\s*', '', title)
        current_line += 1
    
    if not title:
        raise ValueError("No title (H1) found in the document")
    
    # Find the subtitle (next non-empty line)
    subtitle = None
    while current_line < len(lines) and not subtitle:
        if lines[current_line].strip():
            subtitle = lines[current_line].strip()
        current_line += 1
    
    if not subtitle:
        raise ValueError("No subtitle found after the title")
    
    # Parse sections
    sections = []
    current_section = None
    current_ingredients = []
    current_instructions = []
    in_footer = False
    footer_lines = []
    
    while current_line < len(lines):
        line = lines[current_line].strip()
        current_line += 1
        
        # Check for horizontal rule (footer delimiter)
        if re.match(r'^[\*\-_]\s*[\*\-_]\s*[\*\-_][\s\*\-_]*$', line):
            in_footer = True
            if current_section:
                current_section.instructions = '\n\n'.join(current_instructions)
                sections.append(current_section)
            continue
            
        # Handle footer content
        if in_footer:
            if line:
                footer_lines.append(line)
            continue
            
        # Skip empty lines
        if not line:
            continue
            
        # Check for section header
        is_h2 = False
        next_line = lines[current_line] if current_line < len(lines) else ''
        if re.match(r'^-+$', next_line.strip()):  # Setext-style
            is_h2 = True
            current_line += 1
        elif line.startswith('##'):  # ATX-style
            is_h2 = True
            line = re.sub(r'^##\s*', '', line)
            
        if is_h2:
            # Save previous section if it exists
            if current_section:
                current_section.instructions = '\n\n'.join(current_instructions)
                sections.append(current_section)
            
            current_section = Section(title=line)
            current_ingredients = []
            current_instructions = []
            continue
            
        # Handle ingredients list
        if line.startswith(('*', '-')):
            if not current_section:
                raise ValueError("Found ingredients list before any section header")
            ingredient = parse_ingredient(line)
            current_ingredients.append(ingredient)
            if not current_section.ingredients:
                current_section.ingredients = []
            current_section.ingredients.append(ingredient)
        # Handle instructions
        elif line:
            if not current_section:
                raise ValueError("Found instructions before any section header")
            current_instructions.append(line)
    
    # Add the last section if it exists
    if current_section and not in_footer:
        current_section.instructions = '\n\n'.join(current_instructions)
        sections.append(current_section)
    
    if not sections:
        raise ValueError("No sections found in the document")
    
    return {
        'title': title,
        'subtitle': subtitle,
        'recipe_id': transform_filename(file_path.name),
        'sections': sections,
        'footer': '\n\n'.join(footer_lines) if footer_lines else None
    }

def collect_recipe_data(recipes_dir: Path) -> List[Dict]:
    """Collect title and ID information from all recipe files."""
    recipes = []
    for recipe_file in recipes_dir.glob('*.txt'):
        try:
            recipe_data = parse_markdown_file(recipe_file)
            recipes.append({
                'id': recipe_data['recipe_id'],
                'title': recipe_data['title']
            })
        except Exception as e:
            print(f"Error reading {recipe_file}: {str(e)}")
    return sorted(recipes, key=lambda x: x['title'].lower())

def generate_index(output_dir: Path, env: jinja2.Environment, recipes: List[Dict]) -> None:
    """Generate an index.html file listing all recipes."""
    try:
        template = env.get_template('./templates/web/index-template.jinja')
        output = template.render(recipes=recipes)
        
        output_path = output_dir / 'index.html'
        output_path.write_text(output)
        print(f"Successfully generated index at {output_path}")
    except Exception as e:
        print(f"Error generating index: {str(e)}")

def generate_all_recipes(output_dir: Path, env: jinja2.Environment, recipes_dir: Path) -> None:
        """Generate a single page containing all recipes."""
        all_recipes = []
        for recipe_file in recipes_dir.glob('*.txt'):
            try:
                recipe_data = parse_markdown_file(recipe_file)
                all_recipes.append(recipe_data)
            except Exception as e:
                print(f"Error reading {recipe_file}: {str(e)}")
                
        all_recipes.sort(key=lambda x: x['title'].lower())
        template = env.get_template('./templates/web/all-template.jinja')
        output = template.render(recipes=all_recipes)
        
        output_path = output_dir / 'all.html'
        output_path.write_text(output)
        print(f"Successfully generated all-recipes page at {output_path}")
        
def convert_recipe(input_path: Path, output_dir: Path, env: jinja2.Environment) -> None:
    """Convert a single recipe from Markdown to HTML."""
    try:
        # Parse the markdown file
        recipe_data = parse_markdown_file(input_path)
        
        # Generate standardized filename
        recipe_id = recipe_data['recipe_id']
        
        # Render the template
        template = env.get_template('./templates/web/recipe-template.jinja')
        output = template.render(**recipe_data)
        
        # Write the HTML output with transformed filename
        html_output_path = output_dir / f"{recipe_id}.html"
        html_output_path.write_text(output)
        
        # Copy the text file with transformed filename
        text_output_path = output_dir / f"{recipe_id}.txt"
        shutil.copy2(input_path, text_output_path)
        
        print(f"Successfully processed {input_path}")
        print(f"  - HTML: {html_output_path}")
        print(f"  - Text: {text_output_path}")
        
    except Exception as e:
        print(f"Error processing {input_path}: {str(e)}")

def main():
    # Check for recipes directory
    recipes_dir = Path('recipes')
    if not recipes_dir.exists() or not recipes_dir.is_dir():
        print("Error: 'recipes' directory not found in current folder")
        sys.exit(1)
    
    # Check for template file
    template_path = Path('./templates/web/recipe-template.jinja')
    if not template_path.exists():
        print(f"Error: Template file '{template_path}' does not exist")
        sys.exit(1)
    
    # Create output directory if it doesn't exist
    output_dir = Path('output/web')
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Set up Jinja environment
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader('.'),
        autoescape=jinja2.select_autoescape(['html', 'xml']),
        trim_blocks=True,
        lstrip_blocks=True
    )
    
    # Add markdown filter
    env.filters['markdown'] = markdown_to_html
    
    # Collect recipe data for index
    recipes = collect_recipe_data(recipes_dir)
    
    # Process all .txt files in recipes directory
    text_files = recipes_dir.glob('*.txt')
    files_processed = 0
    
    # Generate individual recipe pages and copy text files
    for input_path in text_files:
        convert_recipe(input_path, output_dir, env)
        files_processed += 1
    
    if files_processed == 0:
        print("No .txt files found in 'recipes' directory")
    else:
        print(f"\nProcessed {files_processed} recipe files")
        
        # Generate index page
        generate_index(output_dir, env, recipes)
        
        # After generate_index call:
        generate_all_recipes(output_dir, env, recipes_dir)
        
        # Copy web_resources folder to output directory
        web_resources_dir = Path('resources/web')
        if web_resources_dir.exists() and web_resources_dir.is_dir():
            for item in web_resources_dir.iterdir():
                dest = output_dir / item.name
                if item.is_dir():
                    shutil.copytree(item, dest, dirs_exist_ok=True)
                else:
                    shutil.copy2(item, dest)
            print(f"Copied resources from {web_resources_dir} to {output_dir}")
        else:
            print("No 'web_resources' folder found or it is not a directory")

if __name__ == '__main__':
    main()