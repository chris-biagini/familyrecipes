/**
 * Registry mapping string keys to CodeMirror classifier and fold-service
 * extensions. Bridges the gap between Stimulus values (strings) and the
 * JavaScript objects that createEditor() needs.
 *
 * - plaintext_editor_controller: looks up classifier/foldService by key
 * - recipe_classifier.js: provides recipeClassifier ViewPlugin
 * - quickbites_classifier.js: provides quickbitesClassifier ViewPlugin
 * - recipe_fold.js: provides recipeFoldService
 */
import { recipeClassifier } from "./recipe_classifier"
import { quickbitesClassifier } from "./quickbites_classifier"
import { recipeFoldService } from "./recipe_fold"

export const classifiers = {
  recipe: recipeClassifier,
  quickbites: quickbitesClassifier
}

export const foldServices = {
  recipe: recipeFoldService
}
