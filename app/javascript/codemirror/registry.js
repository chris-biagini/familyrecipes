/**
 * Registry mapping string keys to CodeMirror classifier and fold-service
 * extensions. Bridges the gap between Stimulus values (strings) and the
 * JavaScript objects that createEditor() needs.
 *
 * - plaintext_editor_controller: looks up classifier/foldService by key
 * - recipe_classifier.js: provides recipeClassifier ViewPlugin
 * - quickbites_classifier.js: provides quickbitesClassifier ViewPlugin
 * - markdown_fold.js: provides markdownFoldService
 */
import { recipeClassifier } from "./recipe_classifier"
import { quickbitesClassifier } from "./quickbites_classifier"
import { markdownFoldService } from "./markdown_fold"

export const classifiers = {
  recipe: recipeClassifier,
  quickbites: quickbitesClassifier
}

export const foldServices = {
  markdown: markdownFoldService
}
